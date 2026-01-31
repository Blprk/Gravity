use gravity_core::{Filename, Rule, Pipeline, Context, Engine, FileSystem};
use proptest::prelude::*;
use std::path::{Path, PathBuf};
use std::collections::HashSet;

// Mock FS for testing collisions and rollbacks without hitting disk
pub struct MockFS {
    files: HashSet<PathBuf>,
}

impl FileSystem for MockFS {
    fn exists(&self, path: &Path) -> bool {
        self.files.contains(path)
    }
    fn is_dir(&self, _path: &Path) -> bool { false }
    fn rename(&self, _from: &Path, _to: &Path) -> std::io::Result<()> { Ok(()) }
    fn metadata(&self, _path: &Path) -> std::io::Result<std::fs::Metadata> { 
        Err(std::io::Error::new(std::io::ErrorKind::Other, "Mock metadata not implemented"))
    }
    fn is_case_sensitive(&self, _path: &Path) -> bool { true }
}

proptest! {
    #[test]
    fn test_rename_preserves_extension(base in ".*", ext in ".*") {
        let original = Filename { base: base.clone(), extension: Some(ext.clone()) };
        let rule = Rule::StripPrefix { prefix: "foo".to_string() };
        let context = Context { index: 0 };
        let result = rule.execute(&original, &context);
        
        assert_eq!(result.extension, Some(ext));
    }

    #[test]
    fn test_preview_detects_all_collisions(
        names in proptest::collection::vec(".*", 2..10)
    ) {
        let fs = MockFS { files: HashSet::new() };
        let engine = Engine::new(&fs);
        
        // Rule that renames everything to "constant"
        let pipeline = Pipeline {
            rules: vec![Rule::RegexReplace { 
                pattern: ".*".to_string(), 
                replacement: "constant".to_string() 
            }]
        };

        let files: Vec<PathBuf> = names.iter().map(|n| PathBuf::from(n)).collect();
        let results = engine.generate_preview(&files, &pipeline);

        // All results should have a collision conflict because they all rename to the same thing
        for item in results {
            assert!(item.conflicts.iter().any(|c| matches!(c, gravity_core::Conflict::Collision { .. })));
        }
    }
}
