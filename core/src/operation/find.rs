use std::error::Error;
use std::str::FromStr;

use bumpalo::Bump;
use regex::Regex;

use crate::util::str::remove_lines_postfix;
use crate::util::tree::{DirTree, FilterType, PrintConfig, TreeConfig};

pub fn find_term(
    terms: &Vec<&str>,
    tree_cfg: &TreeConfig,
    print_cfg: &PrintConfig,
) -> Result<String, Box<dyn Error>> {
    let mut config = tree_cfg.clone();
    config.filter_type = FilterType::Include;
    config.filters = terms.iter().map(|term| Regex::new(term)).collect::<Result<Vec<_>, _>>()?;
    let bump = Bump::new();
    let tree = DirTree::new(&config, &bump)?;
    let result = tree.print_tree(&print_cfg)?;
    let mut header = String::from_str("Search Terms: ")?;
    for term in terms {
        header.push_str(term);
        header.push_str(", ");
    }
    header.pop();
    header.pop();

    Ok(format!("{}\n{}", header, remove_lines_postfix(&result, ".gpg")))
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;
    use crate::util::defer::cleanup;
    use crate::util::test_util::{create_dir_structure, gen_unique_temp_dir};

    #[test]
    fn test_find_term() {
        let (_tmp_dir, root) = gen_unique_temp_dir();
        // structure:
        // root
        // ├── apple_banana_cherry.gpg
        // ├── date_elderberry_fig.gpg
        // ├── grape_honeydew_kiwi.gpg
        // ├── fruits
        // │   ├── lemon_mango_nectarine.gpg
        // │   ├── orange_papaya_quince.gpg
        // │   └── raspberry_strawberry_tangerine.gpg
        // ├── fruits/tropical
        // │   ├── apricot_blueberry_coconut.gpg
        // │   ├── dragonfruit_guava_jackfruit.gpg
        // │   └── lime_mulberry_olive.gpg
        // ├── fruits/citrus
        // │   ├── lemon_lime_orange.gpg
        // │   ├── grapefruit_tangerine.gpg
        // │   └── pomelo_clementine.gpg
        // ├── vegetables
        // │   ├── carrot_daikon_eggplant.gpg
        // │   ├── fennel_garlic_horseradish.gpg
        // │   └── iceberg_jalapeno_kale.gpg
        // ├── vegetables/leafy_greens
        // │   ├── kale_spinach_lettuce.gpg
        // │   ├── arugula_collard_mustard.gpg
        // │   └── chard_bok_choy.gpg
        // ├── vegetables/root_vegetables
        // │   ├── carrot_radish_turnip.gpg
        // │   ├── beet_potato_yam.gpg
        // │   └── ginger_turmeric.gpg
        // ├── spices
        // │   ├── anise_basil_cardamom.gpg
        // │   ├── cinnamon_cumin_dill.gpg
        // │   └── fennel_ginger_horseradish.gpg
        // ├── spices/blends
        // │   ├── curry_powder.gpg
        // │   ├── garam_masala.gpg
        // │   └── herbes_de_provence.gpg
        // ├── spices/seeds
        // │   ├── cumin_coriander_fennel.gpg
        // │   ├── mustard_sesame_poppy.gpg
        // │   └── caraway_dill.gpg
        // ├── nuts_and_seeds
        // │   ├── almond_cashew_pistachio.gpg
        // │   ├── walnut_pecan_hazelnut.gpg
        // │   ├── sunflower_pumpkin_flax.gpg
        // │   ├── nuts_and_seeds/roasted
        // │   │   ├── roasted_almonds.gpg
        // │   │   ├── roasted_cashews.gpg
        // │   │   └── roasted_pumpkin_seeds.gpg
        // │   └── nuts_and_seeds/raw
        // │       ├── raw_almonds.gpg
        // │       ├── raw_cashews.gpg
        // │       └── raw_pumpkin_seeds.gpg
        // └── herbs
        //     ├── basil_thyme_rosemary.gpg
        //     ├── parsley_cilantro_dill.gpg
        //     ├── mint_lemongrass_chives.gpg
        //     ├── herbs/dried
        //     │   ├── dried_basil.gpg
        //     │   ├── dried_thyme.gpg
        //     │   └── dried_rosemary.gpg
        //     └── herbs/fresh
        //         ├── fresh_basil.gpg
        //         ├── fresh_thyme.gpg
        //         └── fresh_rosemary.gpg

        let structure: &[(Option<&str>, &[&str])] = &[
            (
                None,
                &["apple_banana_cherry.gpg", "date_elderberry_fig.gpg", "grape_honeydew_kiwi.gpg"]
                    [..],
            ),
            (
                Some("fruits"),
                &[
                    "lemon_mango_nectarine.gpg",
                    "orange_papaya_quince.gpg",
                    "raspberry_strawberry_tangerine.gpg",
                ][..],
            ),
            (
                Some("fruits/tropical"),
                &[
                    "apricot_blueberry_coconut.gpg",
                    "dragonfruit_guava_jackfruit.gpg",
                    "lime_mulberry_olive.gpg",
                ][..],
            ),
            (
                Some("fruits/citrus"),
                &["lemon_lime_orange.gpg", "grapefruit_tangerine.gpg", "pomelo_clementine.gpg"][..],
            ),
            (
                Some("vegetables"),
                &[
                    "carrot_daikon_eggplant.gpg",
                    "fennel_garlic_horseradish.gpg",
                    "iceberg_jalapeno_kale.gpg",
                ][..],
            ),
            (
                Some("vegetables/leafy_greens"),
                &["kale_spinach_lettuce.gpg", "arugula_collard_mustard.gpg", "chard_bok_choy.gpg"]
                    [..],
            ),
            (
                Some("vegetables/root_vegetables"),
                &["carrot_radish_turnip.gpg", "beet_potato_yam.gpg", "ginger_turmeric.gpg"][..],
            ),
            (
                Some("spices"),
                &[
                    "anise_basil_cardamom.gpg",
                    "cinnamon_cumin_dill.gpg",
                    "fennel_ginger_horseradish.gpg",
                ][..],
            ),
            (
                Some("spices/blends"),
                &["curry_powder.gpg", "garam_masala.gpg", "herbes_de_provence.gpg"][..],
            ),
            (
                Some("spices/seeds"),
                &["cumin_coriander_fennel.gpg", "mustard_sesame_poppy.gpg", "caraway_dill.gpg"][..],
            ),
            (
                Some("nuts_and_seeds"),
                &[
                    "almond_cashew_pistachio.gpg",
                    "walnut_pecan_hazelnut.gpg",
                    "sunflower_pumpkin_flax.gpg",
                ][..],
            ),
            (
                Some("nuts_and_seeds/roasted"),
                &["roasted_almonds.gpg", "roasted_cashews.gpg", "roasted_pumpkin_seeds.gpg"][..],
            ),
            (
                Some("nuts_and_seeds/raw"),
                &["raw_almonds.gpg", "raw_cashews.gpg", "raw_pumpkin_seeds.gpg"][..],
            ),
            (
                Some("herbs"),
                &[
                    "basil_thyme_rosemary.gpg",
                    "parsley_cilantro_dill.gpg",
                    "mint_lemongrass_chives.gpg",
                ][..],
            ),
            (
                Some("herbs/dried"),
                &["dried_basil.gpg", "dried_thyme.gpg", "dried_rosemary.gpg"][..],
            ),
            (
                Some("herbs/fresh"),
                &["fresh_basil.gpg", "fresh_thyme.gpg", "fresh_rosemary.gpg"][..],
            ),
        ];
        create_dir_structure(&root, structure);

        cleanup!(
            {
                let config = TreeConfig {
                    root: &root,
                    target: "",
                    filter_type: FilterType::Include,
                    filters: Vec::new(),
                };
                let print_cfg = PrintConfig {
                    dir_color: None,
                    file_color: None,
                    symbol_color: None,
                    tree_color: None,
                };
                let mut terms = vec!["apple"];
                let res = find_term(&terms, &config, &print_cfg).unwrap();
                assert_eq!(
                    res,
                    r#"Search Terms: apple
└── apple_banana_cherry"#
                );

                terms.push("nuts");
                let res = find_term(&terms, &config, &print_cfg).unwrap();
                assert_eq!(
                    res,
                    r#"Search Terms: apple, nuts
├── apple_banana_cherry
└── nuts_and_seeds
    ├── almond_cashew_pistachio
    ├── raw
    │   ├── raw_almonds
    │   ├── raw_cashews
    │   └── raw_pumpkin_seeds
    ├── roasted
    │   ├── roasted_almonds
    │   ├── roasted_cashews
    │   └── roasted_pumpkin_seeds
    ├── sunflower_pumpkin_flax
    └── walnut_pecan_hazelnut"#
                );
            },
            {}
        )
    }
}
