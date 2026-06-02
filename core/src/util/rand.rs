use rand::{self, distr, RngExt};

pub(crate) fn rand_alphabet_string(length: usize) -> String {
    rand::rng().sample_iter(&distr::Alphanumeric).take(length).map(char::from).collect()
}
