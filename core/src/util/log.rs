use chrono::Local;
use lazy_static::lazy_static;
use log::{info, LevelFilter, Log, Metadata, Record};
use parking_lot::RwLock;

lazy_static! {
    static ref LOG_LEVEL: RwLock<LevelFilter> = RwLock::new(LevelFilter::Info);
}

struct DynamicLogger;

impl Log for DynamicLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        metadata.level() <= *LOG_LEVEL.read()
    }

    fn log(&self, record: &Record) {
        if self.enabled(record.metadata()) {
            let now = Local::now();
            println!(
                "[{}] [{}] - {}",
                now.format("%Y-%m-%d %H:%M:%S"),
                record.level(),
                record.args()
            );
        }
    }

    fn flush(&self) {}
}

pub fn init_logger() {
    log::set_logger(&DynamicLogger).unwrap();
    log::set_max_level(LevelFilter::Trace);
}

pub fn set_log_level(level: LevelFilter) {
    *LOG_LEVEL.write() = level;
    info!("Log level set to {:?}!", level);
}

pub fn init_debug_logger() {
    init_logger();
    set_log_level(LevelFilter::Debug);
}
