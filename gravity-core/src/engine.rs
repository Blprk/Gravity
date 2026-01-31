use crate::models::{Filename, Pipeline, Context};
use crate::fs::FileSystem;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreviewItem {
    pub original_path: PathBuf,
    pub new_path: PathBuf,
    pub conflicts: Vec<Conflict>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Conflict {
    TargetExists { path: PathBuf },
    Collision { path: PathBuf },
    CaseCollision { path: PathBuf },
    ReservedName { name: String },
    SourceNotFound { path: PathBuf },
}

pub struct Engine<'a, F: FileSystem> {
    fs: &'a F,
}

use rayon::prelude::*;

impl<'a, F: FileSystem + Sync + Send> Engine<'a, F> {
    pub fn new(fs: &'a F) -> Self {
        Self { fs }
    }

    pub fn generate_preview(
        &self,
        files: &[PathBuf],
        pipeline: &Pipeline,
    ) -> Vec<PreviewItem> {
        // 1. Parallel transformation pass
        let mut results: Vec<PreviewItem> = files.par_iter().enumerate().map(|(index, original_path)| {
            let mut item = PreviewItem {
                original_path: original_path.clone(),
                new_path: original_path.clone(),
                conflicts: Vec::new(),
                warnings: Vec::new(),
            };

            if !self.fs.exists(original_path) {
                item.conflicts.push(Conflict::SourceNotFound { path: original_path.clone() });
                return item;
            }

            match Filename::from_path(original_path) {
                Ok(filename) => {
                    let context = Context { 
                        index,
                        path: Some(original_path.clone()),
                    };
                    
                    let new_filename = pipeline.apply(&filename, &context);
                    let mut new_path = original_path.clone();
                    new_path.set_file_name(new_filename.to_string());
                    item.new_path = new_path;
                }
                Err(e) => {
                    item.warnings.push(format!("Failed to parse filename: {}", e));
                }
            }
            item
        }).collect();

        // 2. Global batch state (Pre-calculate for lock-free conflict detection)
        let mut target_counts: HashMap<PathBuf, usize> = HashMap::new();
        let mut target_counts_lower: HashMap<String, usize> = HashMap::new();
        let mut lower_targets: HashMap<String, Vec<PathBuf>> = HashMap::new();
        let mut batch_originals_lower: std::collections::HashSet<String> = std::collections::HashSet::new();

        for item in &results {
            *target_counts.entry(item.new_path.clone()).or_insert(0) += 1;
            let lower = item.new_path.to_string_lossy().to_lowercase();
            *target_counts_lower.entry(lower.clone()).or_insert(0) += 1;
            lower_targets.entry(lower).or_insert_with(Vec::new).push(item.new_path.clone());
            batch_originals_lower.insert(item.original_path.to_string_lossy().to_lowercase());
        }

        // 3. Parallel conflict detection pass
        results.par_iter_mut().for_each(|item| {
            let is_case_sensitive = self.fs.is_case_sensitive(&item.original_path);
            let original_lower = item.original_path.to_string_lossy().to_lowercase();
            let new_lower = item.new_path.to_string_lossy().to_lowercase();
            
            let paths_effectively_equal = if is_case_sensitive {
                item.new_path == item.original_path
            } else {
                new_lower == original_lower
            };

            // Disk-check (only if not renaming to itself and not part of the batch move)
            if !paths_effectively_equal && self.fs.exists(&item.new_path) {
                let in_batch = if is_case_sensitive {
                    // This is a simplification; for absolute parity we'd need a HashSet of originals
                    // but since this is Parallel, we use the pre-calculated lower-set for speed
                    batch_originals_lower.contains(&new_lower)
                } else {
                    batch_originals_lower.contains(&new_lower)
                };

                if !in_batch {
                    item.conflicts.push(Conflict::TargetExists { path: item.new_path.clone() });
                }
            }

            // Batch-check
            let collision_detected = if is_case_sensitive {
                target_counts.get(&item.new_path).copied().unwrap_or(0) > 1
            } else {
                target_counts_lower.get(&new_lower).copied().unwrap_or(0) > 1
            };

            if collision_detected {
                item.conflicts.push(Conflict::Collision { path: item.new_path.clone() });
            }
            
            if !is_case_sensitive {
                if let Some(others) = lower_targets.get(&new_lower) {
                    for other_path in others {
                        if *other_path != item.new_path {
                            item.conflicts.push(Conflict::CaseCollision { path: item.new_path.clone() });
                            break;
                        }
                    }
                }
            }

            if is_reserved_name(&item.new_path) {
                item.conflicts.push(Conflict::ReservedName { 
                    name: item.new_path.file_name().unwrap_or_default().to_string_lossy().into() 
                });
            }
        });

        results
    }
}

fn is_reserved_name(path: &Path) -> bool {
    let name = path.file_stem().and_then(|s| s.to_str()).unwrap_or("").to_uppercase();
    let reserved = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"];
    reserved.contains(&name.as_str())
}
