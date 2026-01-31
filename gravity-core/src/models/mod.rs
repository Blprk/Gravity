use serde::{Deserialize, Serialize};
use std::path::Path;
use chrono::TimeZone;
use unicode_normalization::UnicodeNormalization;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum GravityError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Normalization error")]
    Normalization,
    #[error("Rule execution failed: {0}")]
    RuleError(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Filename {
    pub base: String,
    pub extension: Option<String>,
}

impl Filename {
    pub fn from_path(path: &Path) -> Result<Self, GravityError> {
        let file_name = path
            .file_name()
            .and_then(|s| s.to_str())
            .ok_or_else(|| GravityError::RuleError("Invalid path".to_string()))?;

        // Normalize to NFC
        let normalized: String = file_name.nfc().collect();
        
        let path_obj = Path::new(&normalized);
        let extension = path_obj.extension().and_then(|s| s.to_str()).map(|s| s.to_string());
        let base = path_obj
            .file_stem()
            .and_then(|s| s.to_str())
            .map(|s| s.to_string())
            .unwrap_or_else(|| "".to_string());

        Ok(Filename { base, extension })
    }

    pub fn to_string(&self) -> String {
        match &self.extension {
            Some(ext) => format!("{}.{}", self.base, ext),
            None => self.base.clone(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Rule {
    StripPrefix { prefix: String },
    StripSuffix { suffix: String },
    RegexReplace { pattern: String, replacement: String },
    CaseTransform { transform: CaseType },
    Literal { text: String, position: Position },
    Counter { padding: usize, start: usize, step: usize, separator: String },
    DateInsertion { format: String, source: DateSource },
    FilterContent { filter: FilterType },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FilterType {
    Numbers,
    Letters,
    Whitespace,
    Symbols,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CaseType {
    Lowercase,
    Uppercase,
    Titlecase,
    CamelCase,
    SnakeCase,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Position {
    Start,
    End,
    Index(usize),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DateSource {
    Current,
    Created,
    Modified,
    Exif,
}

pub struct Pipeline {
    pub rules: Vec<Rule>,
}

impl Pipeline {
    pub fn apply(&self, original: &Filename, context: &Context) -> Filename {
        let mut current = original.clone();
        for rule in &self.rules {
            current = rule.execute(&current, context);
        }
        current
    }
}

pub struct Context {
    pub index: usize,
    pub path: Option<std::path::PathBuf>,
}

impl Rule {
    pub fn execute(&self, filename: &Filename, context: &Context) -> Filename {
        let mut base = filename.base.clone();
        let extension = filename.extension.clone();

        match self {
            Rule::StripPrefix { prefix } => {
                if base.starts_with(prefix) {
                    base = base.replacen(prefix, "", 1);
                }
            }
            Rule::StripSuffix { suffix } => {
                if base.ends_with(suffix) {
                    let end = base.len() - suffix.len();
                    base.truncate(end);
                }
            }
            Rule::RegexReplace { pattern, replacement } => {
                if let Ok(re) = regex::Regex::new(pattern) {
                    base = re.replace_all(&base, replacement).to_string();
                }
            }
            Rule::CaseTransform { transform } => {
                base = match transform {
                    CaseType::Lowercase => base.to_lowercase(),
                    CaseType::Uppercase => base.to_uppercase(),
                    // Basic title case for now
                    CaseType::Titlecase => {
                        let mut c = base.chars();
                        match c.next() {
                            None => String::new(),
                            Some(f) => f.to_uppercase().collect::<String>() + &c.as_str().to_lowercase(),
                        }
                    }
                    _ => base, // TODO: Implement others
                };
            }
            Rule::Literal { text, position } => {
                match position {
                    Position::Start => base = format!("{}{}", text, base),
                    Position::End => base = format!("{}{}", base, text),
                    Position::Index(i) => {
                        if *i <= base.len() {
                            base.insert_str(*i, text);
                        } else {
                            base.push_str(text);
                        }
                    }
                }
            }
            Rule::Counter { padding, start, step, separator } => {
                let val = start + (context.index * step);
                let counter_str = format!("{}{:0>width$}", separator, val, width = padding);
                base.push_str(&counter_str);
            }
            Rule::DateInsertion { format, source } => {
                let mut date_time: Option<chrono::DateTime<chrono::Local>> = None;

                if let Some(path) = &context.path {
                    match source {
                        DateSource::Current => {
                            date_time = Some(chrono::Local::now());
                        }
                        DateSource::Created => {
                            if let Ok(metadata) = std::fs::metadata(path) {
                                if let Ok(created) = metadata.created() {
                                    date_time = Some(chrono::DateTime::from(created));
                                }
                            }
                        }
                        DateSource::Modified => {
                            if let Ok(metadata) = std::fs::metadata(path) {
                                if let Ok(modified) = metadata.modified() {
                                    date_time = Some(chrono::DateTime::from(modified));
                                }
                            }
                        }
                        DateSource::Exif => {
                            if let Ok(file) = std::fs::File::open(path) {
                                let mut bufreader = std::io::BufReader::new(file);
                                if let Ok(exif) = exif::Reader::new().read_from_container(&mut bufreader) {
                                    if let Some(field) = exif.get_field(exif::Tag::DateTimeOriginal, exif::In::PRIMARY) {
                                        let val = field.display_value().to_string();
                                        // EXIF date usually: "2023:10:27 10:23:45"
                                        if let Ok(naive) = chrono::NaiveDateTime::parse_from_str(&val, "%Y:%m:%d %H:%M:%S") {
                                            if let Some(local) = chrono::Local.from_local_datetime(&naive).single() {
                                                date_time = Some(local);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                let date_str = date_time
                    .map(|dt| dt.format(format).to_string())
                    .unwrap_or_else(|| "".to_string());
                base.push_str(&date_str);
            }
            Rule::FilterContent { filter } => {
                let current_base = base.clone();
                base.clear();
                for c in current_base.chars() {
                    let should_remove = match filter {
                        FilterType::Numbers => c.is_numeric(),
                        FilterType::Letters => c.is_alphabetic(),
                        FilterType::Whitespace => c.is_whitespace(),
                        FilterType::Symbols => !c.is_alphanumeric() && !c.is_whitespace(),
                    };
                    if !should_remove {
                        base.push(c);
                    }
                }
            }
        }

        Filename { base, extension }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use unicode_normalization::UnicodeNormalization;
    use std::path::PathBuf;

    #[test]
    fn test_strip_prefix() {
        let rule = Rule::StripPrefix { prefix: "IMG_".to_string() };
        let filename = Filename { base: "IMG_001".to_string(), extension: Some("jpg".to_string()) };
        let context = Context { index: 0, path: None };
        let result = rule.execute(&filename, &context);
        assert_eq!(result.base, "001");
    }

    #[test]
    fn test_regex_replace() {
        let rule = Rule::RegexReplace { 
            pattern: r"(\d+)".to_string(), 
            replacement: "file_$1".to_string() 
        };
        let filename = Filename { base: "image123".to_string(), extension: None };
        let context = Context { index: 0, path: None };
        let result = rule.execute(&filename, &context);
        assert_eq!(result.base, "imagefile_123");
    }

    #[test]
    fn test_counter() {
        let rule = Rule::Counter { padding: 3, start: 1, step: 2, separator: "_".to_string() };
        let filename = Filename { base: "pic_".to_string(), extension: None };
        let context = Context { index: 0, path: None };
        let result = rule.execute(&filename, &context);
        assert_eq!(result.base, "pic_001");

        let context = Context { index: 1, path: None };
        let result = rule.execute(&filename, &context);
        assert_eq!(result.base, "pic_003");
    }

    #[test]
    fn test_case_transform() {
        let rule = Rule::CaseTransform { transform: CaseType::Titlecase };
        let filename = Filename { base: "HELLO WORLD".to_string(), extension: None };
        let context = Context { index: 0, path: None };
        let result = rule.execute(&filename, &context);
        assert_eq!(result.base, "Hello world");
    }

    #[test]
    fn test_date_insertion_current() {
        let rule = Rule::DateInsertion { 
            format: "%Y".to_string(), 
            source: DateSource::Current 
        };
        let filename = Filename { base: "file".to_string(), extension: None };
        let context = Context { index: 0, path: Some(PathBuf::from("fake.txt")) };
        let result = rule.execute(&filename, &context);
        let current_year = chrono::Local::now().format("%Y").to_string();
        assert!(result.base.contains(&current_year));
    }

    #[test]
    fn test_date_insertion_missing_path() {
        let rule = Rule::DateInsertion { 
            format: "%Y".to_string(), 
            source: DateSource::Modified 
        };
        let filename = Filename { base: "file".to_string(), extension: None };
        let context = Context { index: 0, path: None };
        let result = rule.execute(&filename, &context);
        assert_eq!(result.base, "file"); // Should do nothing if path is missing
    }
}
