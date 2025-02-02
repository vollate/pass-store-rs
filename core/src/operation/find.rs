use std::error::Error;
use std::path::Path;
use std::str::FromStr;

use regex::Regex;

use crate::util::tree::{FilterType, TreeConfig};

pub fn find_term(
    root: &Path,
    terms: &Vec<String>,
    config: &TreeConfig,
) -> Result<String, Box<dyn Error>> {
    let mut config = config.clone();
    config.filter_type = FilterType::Exclude;
    config.filters =
        Some(terms.iter().map(|term| Regex::new(term)).collect::<Result<Vec<_>, _>>()?);
    let result = tree_directory(root, &config)?;
    let mut header = String::from_str("Search Terms: ")?;
    for term in terms {
        header.push_str(term);
        header.push_str(", ");
    }
    header.pop();

    Ok(format!("{}\n{}", header, result))
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;
    use crate::util::test_utils::{
        cleanup_test_dir, create_dir_structure, defer_cleanup, gen_unique_temp_dir,
    };

    #[test]
    fn test_find_term() {
        let root = gen_unique_temp_dir();
        // structure:
        // root
        // ├── fruits
        // │   ├── apple_banana_cherry.gpg
        // │   ├── date_elderberry_fig.gpg
        // │   ├── grape_honeydew_kiwi.gpg
        // │   ├── lemon_mango_nectarine.gpg
        // │   ├── orange_papaya_quince.gpg
        // │   ├── raspberry_strawberry_tangerine.gpg
        // │   ├── ugli_vanilla_watermelon.gpg
        // │   ├── xigua_yellow_zucchini.gpg
        // │   ├── tropical
        // │   │   ├── apricot_blueberry_coconut.gpg
        // │   │   ├── dragonfruit_guava_jackfruit.gpg
        // │   │   ├── lime_mulberry_olive.gpg
        // │   │   ├── peach_pear_pineapple.gpg
        // │   │   ├── plum_pomegranate_raspberry.gpg
        // │   │   ├── strawberry_tomato_ugli.gpg
        // │   │   └── yuzu_artichoke_broccoli.gpg
        // │   └── citrus
        // │       ├── lemon_lime_orange.gpg
        // │       ├── grapefruit_tangerine.gpg
        // │       └── pomelo_clementine.gpg
        // ├── vegetables
        // │   ├── carrot_daikon_eggplant.gpg
        // │   ├── fennel_garlic_horseradish.gpg
        // │   ├── iceberg_jalapeno_kale.gpg
        // │   ├── leek_mushroom_onion.gpg
        // │   ├── parsley_quinoa_radish.gpg
        // │   ├── spinach_turnip_zucchini.gpg
        // │   ├── leafy_greens
        // │   │   ├── kale_spinach_lettuce.gpg
        // │   │   ├── arugula_collard_mustard.gpg
        // │   │   └── chard_bok_choy.gpg
        // │   └── root_vegetables
        // │       ├── carrot_radish_turnip.gpg
        // │       ├── beet_potato_yam.gpg
        // │       └── ginger_turmeric.gpg
        // ├── spices
        // │   ├── anise_basil_cardamom.gpg
        // │   ├── cinnamon_cumin_dill.gpg
        // │   ├── fennel_ginger_horseradish.gpg
        // │   ├── juniper_lavender_mustard.gpg
        // │   ├── nutmeg_oregano_paprika.gpg
        // │   ├── rosemary_sage_thyme.gpg
        // │   ├── turmeric_vanilla_watermelon.gpg
        // │   ├── blends
        // │   │   ├── curry_powder.gpg
        // │   │   ├── garam_masala.gpg
        // │   │   └── herbes_de_provence.gpg
        // │   └── seeds
        // │       ├── cumin_coriander_fennel.gpg
        // │       ├── mustard_sesame_poppy.gpg
        // │       └── caraway_dill.gpg
        // ├── nuts_and_seeds
        // │   ├── almond_cashew_pistachio.gpg
        // │   ├── walnut_pecan_hazelnut.gpg
        // │   ├── sunflower_pumpkin_flax.gpg
        // │   ├── roasted
        // │   │   ├── roasted_almonds.gpg
        // │   │   ├── roasted_cashews.gpg
        // │   │   └── roasted_pumpkin_seeds.gpg
        // │   └── raw
        // │       ├── raw_almonds.gpg
        // │       ├── raw_cashews.gpg
        // │       └── raw_pumpkin_seeds.gpg
        // └── herbs
        //     ├── basil_thyme_rosemary.gpg
        //     ├── parsley_cilantro_dill.gpg
        //     ├── mint_lemongrass_chives.gpg
        //     ├── dried
        //     │   ├── dried_basil.gpg
        //     │   ├── dried_thyme.gpg
        //     │   └── dried_rosemary.gpg
        //     └── fresh
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

        defer_cleanup!(
            {
                let config = TreeConfig::nocolor();
                let res = find_term(&root, &vec!["apple".to_string()], &config).unwrap();
                assert_eq!(res, "fuck");
            },
            {
                cleanup_test_dir(&root);
            }
        )
    }
}
