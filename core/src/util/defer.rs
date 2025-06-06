pub struct Defer<F: FnOnce()> {
    f: Option<F>,
}

impl<F: FnOnce()> Defer<F> {
    pub fn new(f: F) -> Self {
        Defer { f: Some(f) }
    }
}

impl<F: FnOnce()> Drop for Defer<F> {
    fn drop(&mut self) {
        if let Some(f) = self.f.take() {
            f();
        }
    }
}

#[cfg(test)]
macro_rules! cleanup {
    ($test:block, $cleanup:block) => {{
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| $test));
        $cleanup;
        if let Err(err) = result {
            std::panic::resume_unwind(err);
        }
    }};
}

#[cfg(test)]
pub(crate) use cleanup;
