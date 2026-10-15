import Foundation

// OWNER: TESTIMAGES. FIXTURE (review fix E-22): SHA-256 of every built-in canvas's canonical bytes
// (`SpecimenCanvas.forEachCanonicalChunk`: header, Float32 RGBA little-endian, auxiliaries) generated on the Mac
// (Apple M1 Max, macOS 27.2, Swift 6.4; BlurCore at -Onone in `swift test` and -O in a release build: identical) with
// default options, 0 EV, margin 256, no text coverage, at N = 894 and N = 810. `core-test --area TESTIMAGES` checks that
// the Mac still produces exactly these; TESTIMAGES_CanvasHashTests checks that the phone does too.
// Regenerate only when a generator changes on purpose (the core test prints `TESTIMAGES_HASH <id>@<N> <sha>`).
let TESTIMAGES_macCanvasHashes: [String: String] = [
    "night-city@894": "d1b1dc95c03518c07f400ba028e9bfc49ff0ed14443a716d241732ec057252da",
    "siemens-star@894": "512c99c447ffe05246d9ba8b07b3f1d9705268d450f836ffc1a4de16a04ba0ab",
    "zone-plate@894": "fe9dfa6393af3ce430e0121d9128363b310d567f8bb6e9876538ca28adf06504",
    "step-edges@894": "8d5b9b9d7f1095525c01bca0d775a7b41604d9c608adc93213e0e7c933aaf438",
    "noisy-step@894": "b110f1604ca4a1fb721b446b334e00b95f65f98cbb6c1f70a6c2a55de082971d",
    "impulse@894": "8e30058b91173da40d01d5ae6be1cfefc3bd2f4a8712763b8e24b2fdf9367f72",
    "impulse-grid@894": "4f3b15a30b9ba4fa913a83cd1fbd7a134487231174ef7c3faa5cbb4df65a87b1",
    "checkerboard@894": "fd3cc582da59440d48e34e6eb092509dfc10d3cb83fad590e60e17f98b2941ed",
    "stripes@894": "d537f25ca2388259674e2d0976e6fee5a7d4fd9a268cf288f39a96b4bc3df1e4",
    "text@894": "7681d8cadee7c452e7d94b3f15eb1199781cede1f5afc484b50519a6c886f600",
    "ramp@894": "7088d498afa0e4ffd8cd2520cc4d15a3a4a0d5022f0cb2e8b8236baeae3feccb",
    "noise-field@894": "7757a913f5b697d374f6c7c011334c2b6ffe6ee599b177a8ac30125f94e8cbb3",
    "alpha-shape@894": "9eaece02729c81f6520d1ceac04ce6b291bfd7fbb670605e06941a85e71b14c2",
    "edge-bar@894": "223b27323d9d0681ef19db6147c047d313994ad82011d1c0e08dc955aaf6fe4a",
    "rings@894": "7c6c4da8b9a4e949dd3422101133977586c5d28d6c034c0b9d9ce517536ee6ed",
    "material-backdrop@894": "294114a77deea835ec61ef876fd70dd99fdcce93a8605c48b7f344831fde78af",
    "scene-depth@894": "ab6d5ebd9980454d50ec0b04531b3c412940285b2247b8eafe30345cdb921f0d",
    "scene-motion@894": "1294e25e4cda975a7cb3b4429c181d5298b7845cd069fee08787b5a4c12b51d2",
    "aerial@894": "ccab0bdec7fb2890ac15b29efd4a4d5f2bcb1942e72139141b6b7cde79a633df",
    "sun-and-bars@894": "22208bedb222b5450aebdeb14e71ed59a43b79644bb6b20848631660c903921a",
    "guide-pair@894": "dd54894938043ab6de76f12c207b33c38db4cc944d5d258c0162d56c50ac7fc9",
    "photo@894": "5a5579b41d4b93628a94bd433080b5d7744bf91a3eaf1d9d7c66bd690fffda12",
    "night-city@810": "615f61919d3a5b6613272937da51a4511495bdbe5cc2b50c761f73a89419699c",
    "siemens-star@810": "401dcfc162e5a3311b4950f0425e028a84748c96b781cf57964cbdbb354a929f",
    "zone-plate@810": "7843c33aa9bd8e262c42843a3259fb69334e45b44189ad13db8895441518bdaf",
    "step-edges@810": "a1ae51d83c9a400e519ab772ae17bf087abd5bde1210832016df504417e95f6d",
    "noisy-step@810": "787affaffad508777a7787376f81a2ebf0379b31753b83ff9702ba43229a63d3",
    "impulse@810": "f9e0a54f16cb0d0b456a8f8d88a951ca5888400881681668324e641d3f2d5173",
    "impulse-grid@810": "5b34724675035272a2c7e34b46447c3a406f9f53a092644834fe2970e6a20fb4",
    "checkerboard@810": "37ea4179c8fc9ee99a6e8c13c3e87ba4cf5e710ac59aee391a1f89d6c79f3756",
    "stripes@810": "5fb0fbd56a2c846b66d6b2b2f6d263b67b362a5e78bdd0a16e15a3d044318a35",
    "text@810": "b69d2946f35b076bbd8065417206f634b9fab4b88ad394cf12f86575a93d8e8c",
    "ramp@810": "f921f11c647d7c0c0e7c8de89b6d52736a54dfee39dda1fbe4e2e110e1c216d0",
    "noise-field@810": "080628dbf7db919fcec5393f54490870349bfc4ead231a131b7af1bea918aa1a",
    "alpha-shape@810": "fec6ce82b12e0fb7ff94d9a7ad0a992456a1a5f8740c164a90425a9720909d26",
    "edge-bar@810": "265161551b8dc8cf316cedce53e362eeccd5b5f61cd9ba31b1d22530a44ae16b",
    "rings@810": "835fbd56030d8e830aa70422f6e225c20af1d4287a15a67b41929d4868a40fa5",
    "material-backdrop@810": "98bb523f4253519a4b68e6d5f56eb038c83bafc8f03e40fcee5d847834c85283",
    "scene-depth@810": "d33b4bb9084964f4ccfe8c19af012766aac4f5f775859f4a9e6aa96d84944285",
    "scene-motion@810": "28ebb63fa037e159c610b59029357f43acc910ace19a9a1d22cfd4ea1fec7f90",
    "aerial@810": "e31af4ec181e203f138e1c52ac0a5d4ff9db34bfa703ba35222b802ac04c69e7",
    "sun-and-bars@810": "b458a4da1a813d98748a7fc4e0f20857bc5adc80058f35ac40a9bc64f4275a22",
    "guide-pair@810": "a0a585fe635802ba995ff7e11436aa17205c182a7511358bb27b3236ba683a6e",
    "photo@810": "ba3ea9482e159f8555bac1f5242e521ea0c36d23bf73c54082e2a72d8ceef655",
]
