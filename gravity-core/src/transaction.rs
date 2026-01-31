use crate::fs::FileSystem;
use serde::{Deserialize, Serialize};
use std::path::{PathBuf};
use uuid::Uuid;
use std::io;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionStep {
    pub from: PathBuf,
    pub to: PathBuf,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionJournal {
    pub id: Uuid,
    pub phase1: Vec<TransactionStep>,
    pub phase2: Vec<TransactionStep>,
    pub completed: bool,
}

pub struct TransactionExecutor<'a, F: FileSystem> {
    fs: &'a F,
}

impl<'a, F: FileSystem> TransactionExecutor<'a, F> {
    pub fn new(fs: &'a F) -> Self {
        Self { fs }
    }

    pub fn execute(&self, plans: &[(PathBuf, PathBuf)]) -> Result<TransactionJournal, (TransactionJournal, io::Error)> {
        let mut journal = TransactionJournal {
            id: Uuid::new_v4(),
            phase1: Vec::new(),
            phase2: Vec::new(),
            completed: false,
        };

        // Phase 1: Rename to Temporaries
        for (original, _target) in plans {
            let mut temp = original.clone();
            let temp_name = format!("gravity-{}.tmp", Uuid::new_v4());
            temp.set_file_name(temp_name);
            
            if let Err(e) = self.fs.rename(original, &temp) {
                // Rollback Phase 1
                self.rollback_phase1(&journal);
                return Err((journal, e));
            }
            
            journal.phase1.push(TransactionStep {
                from: original.clone(),
                to: temp,
            });
        }

        // Phase 2: Rename to Final Targets
        for (i, (_original, target)) in plans.iter().enumerate() {
            let temp = &journal.phase1[i].to;
            
            if let Err(e) = self.fs.rename(temp, target) {
                // Rollback Phase 2 and then Phase 1
                self.rollback_phase2(&journal);
                self.rollback_phase1(&journal);
                return Err((journal, e));
            }

            journal.phase2.push(TransactionStep {
                from: temp.clone(),
                to: target.clone(),
            });
        }

        journal.completed = true;
        Ok(journal)
    }

    fn rollback_phase1(&self, journal: &TransactionJournal) {
        for step in journal.phase1.iter().rev() {
            let _ = self.fs.rename(&step.to, &step.from);
        }
    }

    fn rollback_phase2(&self, journal: &TransactionJournal) {
        for step in journal.phase2.iter().rev() {
            let _ = self.fs.rename(&step.to, &step.from);
        }
    }

    pub fn undo(&self, journal: &TransactionJournal) -> io::Result<()> {
        if !journal.completed {
            return Err(io::Error::new(io::ErrorKind::Other, "Cannot undo incomplete transaction"));
        }

        // Undo is Phase 2 reverse then Phase 1 reverse
        for step in journal.phase2.iter().rev() {
            self.fs.rename(&step.to, &step.from)?;
        }
        for step in journal.phase1.iter().rev() {
            self.fs.rename(&step.to, &step.from)?;
        }

        Ok(())
    }
}
