use std::path::Path;
use std::io;

pub trait FileSystem {
    fn exists(&self, path: &Path) -> bool;
    fn is_dir(&self, path: &Path) -> bool;
    fn rename(&self, from: &Path, to: &Path) -> io::Result<()>;
    fn metadata(&self, path: &Path) -> io::Result<std::fs::Metadata>;
    fn is_case_sensitive(&self, path: &Path) -> bool;
}

pub struct RealFileSystem;

impl FileSystem for RealFileSystem {
    fn exists(&self, path: &Path) -> bool {
        path.exists()
    }

    fn is_dir(&self, path: &Path) -> bool {
        path.is_dir()
    }

    fn rename(&self, from: &Path, to: &Path) -> io::Result<()> {
        std::fs::rename(from, to)
    }

    fn metadata(&self, path: &Path) -> io::Result<std::fs::Metadata> {
        std::fs::metadata(path)
    }

    fn is_case_sensitive(&self, _path: &Path) -> bool {
        // macOS APFS is usually case-insensitive but case-preserving.
        // A simple check is to try to access a file with different casing.
        // For now, assume case-insensitive on macOS as it's the common case.
        // True detection involves writing a temp file.
        // For the sake of the engine, we'll implement a robust check or allow manual override.
        false
    }
}
