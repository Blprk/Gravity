use clap::{Parser, Subcommand};
use gravity_core::{Engine, Pipeline, RealFileSystem, Rule, TransactionExecutor};
use std::path::PathBuf;
use anyhow::{Context, Result};
use tabled::{Table, Tabled};

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
    /// Directory to save journals in
    #[arg(long, global = true)]
    journal_dir: Option<PathBuf>,
}

#[derive(Subcommand)]
enum Commands {
    /// Preview renames
    Preview {
        #[arg(short, long)]
        rules: PathBuf,
        files: Vec<PathBuf>,
        #[arg(long)]
        json: bool,
    },
    /// Execute renames
    Commit {
        #[arg(short, long)]
        rules: PathBuf,
        files: Vec<PathBuf>,
    },
    /// Undo a previous transaction
    Undo {
        #[arg(short, long)]
        journal: PathBuf,
    },
}

#[derive(Tabled)]
struct PreviewRow {
    #[tabled(rename = "Original")]
    original: String,
    #[tabled(rename = "New Name")]
    new_name: String,
    #[tabled(rename = "Status")]
    status: String,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let fs = RealFileSystem;
    let engine = Engine::new(&fs);

    match cli.command {
        Commands::Preview { rules, files, json } => {
            let pipeline = load_pipeline(&rules)?;
            let results = engine.generate_preview(&files, &pipeline);

            if json {
                println!("{}", serde_json::to_string_pretty(&results)?);
            } else {
                let rows: Vec<PreviewRow> = results.into_iter().map(|item| {
                    let status = if item.conflicts.is_empty() {
                        "OK".to_string()
                    } else {
                        format!("CONFLICT: {:?}", item.conflicts)
                    };
                    PreviewRow {
                        original: item.original_path.file_name().unwrap_or_default().to_string_lossy().to_string(),
                        new_name: item.new_path.file_name().unwrap_or_default().to_string_lossy().to_string(),
                        status,
                    }
                }).collect();
                println!("{}", Table::new(rows).to_string());
            }
        }
        Commands::Commit { rules, files } => {
            let pipeline = load_pipeline(&rules)?;
            let results = engine.generate_preview(&files, &pipeline);

            let mut conflicts = Vec::new();
            for item in &results {
                if !item.conflicts.is_empty() {
                    conflicts.push(item);
                }
            }

            if !conflicts.is_empty() {
                anyhow::bail!("Cannot commit: {} conflicts detected.", conflicts.len());
            }

            let plans: Vec<(PathBuf, PathBuf)> = results.into_iter()
                .map(|item| (item.original_path, item.new_path))
                .collect();

            let executor = TransactionExecutor::new(&fs);
            match executor.execute(&plans) {
                Ok(journal) => {
                    let mut journal_path = cli.journal_dir.clone().unwrap_or_else(|| PathBuf::from("."));
                    if !journal_path.exists() {
                        std::fs::create_dir_all(&journal_path)?;
                    }
                    journal_path.push(format!("journal-{}.json", journal.id));
                    
                    std::fs::write(&journal_path, serde_json::to_string_pretty(&journal)?)?;
                    println!("Rename successful. Journal saved to {}", journal_path.display());
                }
                Err((journal, err)) => {
                    let mut journal_path = cli.journal_dir.clone().unwrap_or_else(|| PathBuf::from("."));
                    if !journal_path.exists() {
                        let _ = std::fs::create_dir_all(&journal_path);
                    }
                    journal_path.push(format!("failed-journal-{}.json", journal.id));

                    println!("Rename failed: {}. Partial journal saved to {}", err, journal_path.display());
                    std::fs::write(&journal_path, serde_json::to_string_pretty(&journal)?)?;
                    anyhow::bail!("Rename failed and was rolled back where possible.");
                }
            }
        }
        Commands::Undo { journal } => {
            let content = std::fs::read_to_string(journal)?;
            let journal_data = serde_json::from_str(&content)?;
            let executor = TransactionExecutor::new(&fs);
            executor.undo(&journal_data)?;
            println!("Undo successful.");
        }
    }

    Ok(())
}

fn load_pipeline(path: &PathBuf) -> Result<Pipeline> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read rules file: {:?}", path))?;
    
    // Support JSON for now
    let rules: Vec<Rule> = serde_json::from_str(&content)
        .with_context(|| "Failed to parse rules JSON")?;
    
    Ok(Pipeline { rules })
}
