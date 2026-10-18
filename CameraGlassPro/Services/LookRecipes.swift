import CoreGraphics

/// Data for the recipe-built filters (generated from the tuned recipe table; each look was checked on
/// night, portrait and nature photos). Rendered by `ImageProcessingService.recipeLook`.
struct LookRecipe {
    let label: String
    let category: FilterCategory
    var exposure: Double = 0
    /// Warmer (+) or cooler (−) white balance shift, in kelvin.
    var temperature: CGFloat = 0
    /// Black and white with these channel weights (e.g. a red filter darkens blue skies).
    var mono: (CGFloat, CGFloat, CGFloat)?
    /// Channel mixing in linear light: rows are the new red, green and blue (e.g. infrared film swaps).
    var mix: [(CGFloat, CGFloat, CGFloat)]?
    /// Black and white reduced to this many tones, colored from the duotone dark color to its light color.
    var posterize: Int?
    var duotone: ((CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat))?
    /// Five-point tone curve (x, y in 0...1).
    var curve: [(CGFloat, CGFloat)]
    var saturation: Double = 1
    var vibrance: Double = 0
    /// Split toning: tint added to shadows (fading out toward pure black) and to highlights.
    var shadows: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
    var highlights: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
    /// Soft highlight bloom amount and local contrast amount.
    var glow: Double = 0
    var clarity: Double = 0

    init(_ label: String, _ category: FilterCategory, exposure: Double = 0, temperature: CGFloat = 0,
         mono: (CGFloat, CGFloat, CGFloat)? = nil, mix: [(CGFloat, CGFloat, CGFloat)]? = nil, posterize: Int? = nil,
         duotone: ((CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat))? = nil, curve: [(CGFloat, CGFloat)], saturation: Double = 1,
         vibrance: Double = 0, shadows: (CGFloat, CGFloat, CGFloat) = (0, 0, 0),
         highlights: (CGFloat, CGFloat, CGFloat) = (0, 0, 0), glow: Double = 0, clarity: Double = 0) {
        self.label = label
        self.category = category
        self.exposure = exposure
        self.temperature = temperature
        self.mono = mono
        self.mix = mix
        self.posterize = posterize
        self.duotone = duotone
        self.curve = curve
        self.saturation = saturation
        self.vibrance = vibrance
        self.shadows = shadows
        self.highlights = highlights
        self.glow = glow
        self.clarity = clarity
    }

    /// The recipe behind a filter, or nil for the hand-built looks in FilterLooks.swift.
    /// (A switch rather than one big dictionary literal, which is slow to type-check.)
    static func recipe(_ filter: PhotoFilter) -> LookRecipe? {
        switch filter {
        case .vividWarm: LookRecipe("Vivid Warm", .classic, temperature: 350.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], vibrance: 0.35)
        case .vividCool: LookRecipe("Vivid Cool", .classic, temperature: -350.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], vibrance: 0.35)
        case .dramatic: LookRecipe("Dramatic", .classic, exposure: -0.15, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 0.9, clarity: 0.35)
        case .dramaticCool: LookRecipe("Dramatic Cool", .classic, exposure: -0.15, temperature: -400.0, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 0.85, clarity: 0.35)
        case .portra160: LookRecipe("Portra 160", .film, temperature: 150.0, curve: [(0.0, 0.02), (0.25, 0.262), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.88, highlights: (0.01, 0.006, 0.0))
        case .superia400: LookRecipe("Superia 400", .film, temperature: -100.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.05, shadows: (-0.004, 0.008, 0.004), highlights: (0.006, 0.006, 0.0))
        case .ektachrome: LookRecipe("Ektachrome E100", .film, temperature: -150.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.1, vibrance: 0.2, shadows: (-0.004, 0.0, 0.012))
        case .velvia50: LookRecipe("Velvia 50", .film, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.28, vibrance: 0.25, shadows: (0.0, 0.0, 0.006))
        case .kodachrome: LookRecipe("Kodachrome", .film, temperature: 200.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.15, shadows: (0.004, 0.0, -0.004), highlights: (0.012, 0.006, -0.004))
        case .hp5: LookRecipe("HP5 Plus", .film, mono: (0.2126, 0.7152, 0.0722), curve: [(0.0, 0.035), (0.25, 0.25), (0.5, 0.51), (0.75, 0.77), (1.0, 0.97)])
        case .provia100f: LookRecipe("Provia 100F", .film, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.08, shadows: (-0.002, 0.0, 0.006))
        case .ultramax400: LookRecipe("UltraMax 400", .film, temperature: 300.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.1, highlights: (0.012, 0.008, -0.006))
        case .tealOrange: LookRecipe("Teal & Orange", .cinematic, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.05, shadows: (-0.014, 0.004, 0.02), highlights: (0.02, 0.008, -0.01))
        case .blockbuster: LookRecipe("Blockbuster", .cinematic, exposure: -0.1, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.1, shadows: (-0.012, 0.004, 0.018), highlights: (0.016, 0.006, -0.008), clarity: 0.2)
        case .moodyNight: LookRecipe("Moody Night", .cinematic, exposure: -0.2, temperature: -300.0, curve: [(0.0, 0.02), (0.25, 0.2), (0.5, 0.47), (0.75, 0.76), (1.0, 0.97)], saturation: 0.85, shadows: (-0.006, 0.0, 0.012))
        case .bleachBypass: LookRecipe("Bleach Bypass", .cinematic, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 0.55, clarity: 0.3)
        case .neonNoir: LookRecipe("Neon Noir", .cinematic, exposure: -0.15, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.15, shadows: (-0.006, -0.004, 0.02), highlights: (0.016, -0.004, 0.012))
        case .matrixGreen: LookRecipe("Matrix Green", .cinematic, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 0.8, shadows: (-0.006, 0.012, -0.002), highlights: (-0.004, 0.012, -0.006))
        case .desertHeat: LookRecipe("Desert Heat", .cinematic, temperature: 600.0, curve: [(0.0, 0.02), (0.25, 0.262), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.95, highlights: (0.018, 0.01, -0.01))
        case .vintageHollywood: LookRecipe("Vintage Hollywood", .cinematic, temperature: 250.0, curve: [(0.0, 0.04), (0.25, 0.274), (0.5, 0.51), (0.75, 0.76), (1.0, 0.95)], saturation: 0.8, shadows: (0.006, 0.002, -0.002), glow: 0.15)
        case .arcticBlue: LookRecipe("Arctic Blue", .cinematic, temperature: -650.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 0.85, shadows: (-0.006, 0.002, 0.014))
        case .sunsetDrama: LookRecipe("Sunset Drama", .cinematic, temperature: 450.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.15, shadows: (0.004, -0.004, 0.012), highlights: (0.02, 0.008, -0.01))
        case .studioClean: LookRecipe("Studio Clean", .portrait, exposure: 0.1, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 0.95)
        case .goldenGlow: LookRecipe("Golden Glow", .portrait, temperature: 350.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.02, highlights: (0.014, 0.01, -0.004), glow: 0.15)
        case .rosy: LookRecipe("Rosy", .portrait, temperature: 100.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 0.98, highlights: (0.012, 0.002, 0.006))
        case .mattePortrait: LookRecipe("Matte Portrait", .portrait, curve: [(0.0, 0.06), (0.25, 0.286), (0.5, 0.51), (0.75, 0.76), (1.0, 0.95)], saturation: 0.9)
        case .brightAiry: LookRecipe("Bright & Airy", .portrait, exposure: 0.3, curve: [(0.0, 0.05), (0.25, 0.3), (0.5, 0.56), (0.75, 0.8), (1.0, 0.98)], saturation: 0.88, shadows: (0.0, 0.002, 0.006))
        case .warmSkin: LookRecipe("Warm Skin", .portrait, temperature: 250.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 0.96, highlights: (0.008, 0.004, 0.0))
        case .softPeach: LookRecipe("Soft Peach", .portrait, temperature: 200.0, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 0.9, highlights: (0.014, 0.006, 0.002), glow: 0.12)
        case .editorial: LookRecipe("Editorial", .portrait, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 0.8, shadows: (-0.002, 0.0, 0.004), clarity: 0.2)
        case .vividGreen: LookRecipe("Vivid Green", .nature, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.12, vibrance: 0.3, shadows: (-0.002, 0.004, 0.0))
        case .deepSky: LookRecipe("Deep Sky", .nature, temperature: -200.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.1, vibrance: 0.25, highlights: (0.0, 0.0, 0.004))
        case .autumn: LookRecipe("Autumn", .nature, temperature: 450.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.12, shadows: (0.004, 0.0, -0.004), highlights: (0.016, 0.006, -0.008))
        case .alpineCool: LookRecipe("Alpine Cool", .nature, temperature: -450.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 0.95, clarity: 0.15)
        case .desertGold: LookRecipe("Desert Gold", .nature, temperature: 550.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.05, highlights: (0.016, 0.01, -0.012))
        case .ocean: LookRecipe("Ocean", .nature, temperature: -300.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.1, vibrance: 0.2, shadows: (-0.006, 0.004, 0.012))
        case .forestMood: LookRecipe("Forest Mood", .nature, exposure: -0.15, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 0.85, shadows: (-0.004, 0.008, 0.002))
        case .springBloom: LookRecipe("Spring Bloom", .nature, exposure: 0.15, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 1.05, vibrance: 0.2, highlights: (0.006, 0.004, 0.004))
        case .silver: LookRecipe("Silver", .blackWhite, mono: (0.2126, 0.7152, 0.0722), curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)])
        case .softMatte: LookRecipe("Soft Matte", .blackWhite, mono: (0.2126, 0.7152, 0.0722), curve: [(0.0, 0.07), (0.25, 0.292), (0.5, 0.51), (0.75, 0.76), (1.0, 0.94)])
        case .highContrast: LookRecipe("High Contrast", .blackWhite, mono: (0.2126, 0.7152, 0.0722), curve: [(0.0, 0.0), (0.25, 0.16), (0.5, 0.5), (0.75, 0.86), (1.0, 1.0)], clarity: 0.25)
        case .selenium: LookRecipe("Selenium", .blackWhite, mono: (0.2126, 0.7152, 0.0722), curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], shadows: (0.004, -0.002, 0.012), highlights: (0.006, 0.004, 0.006))
        case .sepia: LookRecipe("Sepia", .blackWhite, mono: (0.2126, 0.7152, 0.0722), curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], shadows: (0.02, 0.008, -0.01), highlights: (0.06, 0.03, -0.03))
        case .infrared: LookRecipe("Infrared", .blackWhite, mono: (0.15, 1.15, -0.3), curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], glow: 0.2)
        case .platinum: LookRecipe("Platinum", .blackWhite, mono: (0.2126, 0.7152, 0.0722), curve: [(0.0, 0.04), (0.25, 0.274), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], highlights: (0.012, 0.008, 0.002))
        case .cyanotype: LookRecipe("Cyanotype", .blackWhite, mono: (0.2126, 0.7152, 0.0722), curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], shadows: (-0.02, 0.004, 0.04), highlights: (-0.04, 0.0, 0.03))
        case .redFilter: LookRecipe("Red Filter B&W", .blackWhite, mono: (0.7, 0.35, -0.05), curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)])
        case .seventies: LookRecipe("70s", .vintage, temperature: 500.0, curve: [(0.0, 0.05), (0.25, 0.28), (0.5, 0.51), (0.75, 0.76), (1.0, 0.94)], saturation: 0.85, shadows: (0.006, 0.002, -0.004), highlights: (0.016, 0.01, -0.012))
        case .eighties: LookRecipe("80s", .vintage, temperature: -100.0, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 1.1, shadows: (0.004, -0.004, 0.014), highlights: (0.012, 0.002, 0.004))
        case .polaroidFade: LookRecipe("Polaroid Fade", .vintage, temperature: 150.0, curve: [(0.0, 0.07), (0.25, 0.292), (0.5, 0.51), (0.75, 0.76), (1.0, 0.93)], saturation: 0.8, shadows: (-0.004, 0.006, 0.006), highlights: (0.012, 0.008, 0.0))
        case .kodakMoment: LookRecipe("Kodak Moment", .vintage, temperature: 350.0, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 1.05, highlights: (0.016, 0.01, -0.008))
        case .oldPostcard: LookRecipe("Old Postcard", .vintage, temperature: 400.0, curve: [(0.0, 0.06), (0.25, 0.286), (0.5, 0.51), (0.75, 0.76), (1.0, 0.92)], saturation: 0.6, highlights: (0.02, 0.012, -0.008))
        case .sunbleached: LookRecipe("Sunbleached", .vintage, exposure: 0.2, curve: [(0.0, 0.06), (0.25, 0.286), (0.5, 0.51), (0.75, 0.76), (1.0, 0.96)], saturation: 0.7, highlights: (0.01, 0.008, 0.0))
        case .retroTeal: LookRecipe("Retro Teal", .vintage, curve: [(0.0, 0.04), (0.25, 0.274), (0.5, 0.51), (0.75, 0.76), (1.0, 0.96)], saturation: 0.9, shadows: (-0.008, 0.008, 0.012), highlights: (0.014, 0.008, -0.004))
        case .lomo: LookRecipe("Lomo", .vintage, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.25, shadows: (-0.004, 0.0, 0.012), highlights: (0.012, 0.01, -0.006))
        case .darkAcademia: LookRecipe("Dark Academia", .moody, exposure: -0.2, temperature: 300.0, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.94)], saturation: 0.75, shadows: (0.006, 0.002, -0.002))
        case .rainyDay: LookRecipe("Rainy Day", .moody, exposure: -0.1, temperature: -300.0, curve: [(0.0, 0.04), (0.25, 0.274), (0.5, 0.51), (0.75, 0.76), (1.0, 0.95)], saturation: 0.7, shadows: (-0.004, 0.002, 0.01))
        case .midnight: LookRecipe("Midnight", .moody, exposure: -0.35, temperature: -450.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 0.85, shadows: (-0.006, 0.0, 0.016))
        case .foggy: LookRecipe("Foggy", .moody, exposure: 0.1, curve: [(0.0, 0.1), (0.25, 0.31), (0.5, 0.53), (0.75, 0.74), (1.0, 0.92)], saturation: 0.7, glow: 0.18)
        case .emberGlow: LookRecipe("Ember Glow", .moody, exposure: -0.15, temperature: 500.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], highlights: (0.02, 0.008, -0.01), glow: 0.12)
        case .stormy: LookRecipe("Stormy", .moody, exposure: -0.2, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 0.65, shadows: (-0.004, 0.002, 0.008), clarity: 0.3)
        case .shadowBlue: LookRecipe("Shadow Blue", .moody, exposure: -0.1, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 0.9, shadows: (-0.01, 0.002, 0.02))
        case .freshFood: LookRecipe("Fresh", .food, exposure: 0.1, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.1, vibrance: 0.25, clarity: 0.1)
        case .warmBakery: LookRecipe("Warm Bakery", .food, temperature: 400.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.05, highlights: (0.012, 0.008, -0.004))
        case .crispSalad: LookRecipe("Crisp Greens", .food, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.12, vibrance: 0.3, clarity: 0.2)
        case .cafeLatte: LookRecipe("Café Latte", .food, temperature: 300.0, curve: [(0.0, 0.04), (0.25, 0.274), (0.5, 0.51), (0.75, 0.76), (1.0, 0.96)], saturation: 0.85, highlights: (0.012, 0.008, 0.0))
        case .juicy: LookRecipe("Juicy", .food, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.25, vibrance: 0.3)
        case .disposable: LookRecipe("Disposable", .y2k, exposure: 0.1, temperature: 200.0, curve: [(0.0, 0.04), (0.25, 0.25), (0.5, 0.52), (0.75, 0.8), (1.0, 0.97)], saturation: 1.1, shadows: (0.0, 0.006, 0.004), highlights: (0.012, 0.006, -0.004))
        case .bloomPop: LookRecipe("Bloom Pop", .y2k, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.15, vibrance: 0.2, glow: 0.3)
        case .frosted: LookRecipe("Frosted", .y2k, exposure: 0.15, temperature: -300.0, curve: [(0.0, 0.05), (0.25, 0.28), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.85, highlights: (0.0, 0.004, 0.01), glow: 0.2)
        case .cyberPink: LookRecipe("Cyber Pink", .y2k, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.1, shadows: (0.006, -0.004, 0.016), highlights: (0.018, 0.002, 0.012))
        case .cleanPro: LookRecipe("Clean Pro", .quality, curve: [(0.0, 0.0), (0.25, 0.245), (0.5, 0.505), (0.75, 0.765), (1.0, 1.0)], vibrance: 0.15, clarity: 0.15)
        case .vividHDR: LookRecipe("Vivid HDR", .quality, curve: [(0.0, 0.02), (0.25, 0.27), (0.5, 0.52), (0.75, 0.76), (1.0, 0.98)], saturation: 1.05, vibrance: 0.3, clarity: 0.35)
        case .pointShoot: LookRecipe("Point & Shoot", .digicam, temperature: -200.0, curve: [(0.0, 0.01), (0.25, 0.23), (0.5, 0.53), (0.75, 0.82), (1.0, 0.98)], saturation: 1.12, clarity: 0.1)
        case .nightFlash: LookRecipe("Night Flash", .digicam, exposure: 0.2, temperature: -250.0, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.08, glow: 0.15)
        case .coolCCD: LookRecipe("Cool CCD", .digicam, temperature: -450.0, curve: [(0.0, 0.02), (0.25, 0.262), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 1.05, shadows: (-0.004, 0.004, 0.01))
        case .y2006: LookRecipe("2006", .digicam, temperature: 150.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.15, highlights: (0.01, 0.008, 0.0), glow: 0.1)
        case .aerochrome: LookRecipe("Aerochrome", .creative, mix: [(0.6, 0.6, 0.0), (0.45, 0.25, 0.05), (0.05, 0.05, 0.9)], curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.1)
        case .crossProcess: LookRecipe("Cross Process", .creative, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.25, shadows: (-0.008, 0.0, 0.02), highlights: (0.01, 0.02, -0.02))
        case .technicolor: LookRecipe("Technicolor", .creative, temperature: 100.0, mix: [(1.0, 0.0, 0.0), (0.0, 0.75, 0.25), (0.0, 0.3, 0.7)], curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.15)
        case .vaporwave: LookRecipe("Vaporwave", .creative, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 1.2, shadows: (0.02, -0.006, 0.035), highlights: (-0.012, 0.018, 0.02))
        case .synthwave: LookRecipe("Synthwave", .creative, exposure: -0.1, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.2, shadows: (0.018, -0.008, 0.04), highlights: (0.035, 0.008, 0.005), glow: 0.2)
        case .animePastel: LookRecipe("Anime Pastel", .creative, exposure: 0.15, curve: [(0.0, 0.05), (0.25, 0.3), (0.5, 0.56), (0.75, 0.8), (1.0, 0.98)], saturation: 1.12, vibrance: 0.2, highlights: (0.004, 0.004, 0.012), glow: 0.15)
        case .expiredFilm: LookRecipe("Expired Film", .creative, temperature: 200.0, curve: [(0.0, 0.06), (0.25, 0.286), (0.5, 0.51), (0.75, 0.76), (1.0, 0.93)], saturation: 0.85, shadows: (0.004, 0.012, -0.004), highlights: (0.016, 0.004, 0.01))
        case .underwaterFix: LookRecipe("Underwater Fix", .creative, temperature: 400.0, mix: [(1.25, 0.15, 0.05), (0.0, 0.95, 0.0), (0.0, 0.0, 0.88)], curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.1, clarity: 0.2)
        case .springLight: LookRecipe("Spring Light", .seasons, exposure: 0.1, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 1.08, vibrance: 0.25, shadows: (-0.002, 0.006, 0.002), highlights: (0.008, 0.002, 0.008))
        case .summerHeat: LookRecipe("Summer Heat", .seasons, temperature: 450.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.15, vibrance: 0.2, highlights: (0.016, 0.01, -0.008))
        case .winterFrost: LookRecipe("Winter Frost", .seasons, exposure: 0.1, temperature: -500.0, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.85, shadows: (-0.006, 0.002, 0.016), highlights: (0.0, 0.004, 0.01))
        case .goldenHour: LookRecipe("Golden Hour Boost", .seasons, temperature: 900.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.1, highlights: (0.03, 0.018, -0.014), glow: 0.22)
        case .vision3: LookRecipe("Vision3 500T", .film, temperature: -350.0, curve: [(0.0, 0.03), (0.25, 0.25), (0.5, 0.51), (0.75, 0.77), (1.0, 0.96)], saturation: 0.95, shadows: (-0.008, 0.004, 0.014), highlights: (0.016, 0.008, -0.004), glow: 0.12)
        case .agfaVista: LookRecipe("Agfa Vista 200", .film, temperature: -100.0, mix: [(1.08, -0.04, -0.04), (0.0, 1.0, 0.0), (0.0, 0.02, 0.98)], curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.12, shadows: (-0.004, 0.0, 0.01), highlights: (0.012, 0.0, 0.002))
        case .delta3200: LookRecipe("Delta 3200", .blackWhite, mono: (0.2126, 0.7152, 0.0722), curve: [(0.0, 0.03), (0.25, 0.17), (0.5, 0.5), (0.75, 0.85), (1.0, 1.0)], clarity: 0.25)
        case .lomoPurple: LookRecipe("Lomochrome Purple", .creative, mix: [(0.65, 0.35, 0.0), (0.1, 0.1, 0.8), (0.1, 0.65, 0.25)], curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.1)
        case .polaroid600: LookRecipe("Polaroid 600 Faded", .vintage, temperature: -150.0, curve: [(0.0, 0.08), (0.25, 0.298), (0.5, 0.51), (0.75, 0.76), (1.0, 0.92)], saturation: 0.75, shadows: (-0.004, 0.006, 0.014), highlights: (0.01, 0.008, 0.004))
        case .gameBoy: LookRecipe("Game Boy", .creative, mono: (0.2126, 0.7152, 0.0722), posterize: 4, duotone: ((0.06, 0.22, 0.06), (0.61, 0.74, 0.06)), curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)])
        case .tokyoNeon: LookRecipe("Tokyo Neon", .travel, exposure: -0.05, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.25, shadows: (0.01, -0.006, 0.04), highlights: (0.045, -0.006, 0.035), glow: 0.18)
        case .santoriniBlue: LookRecipe("Santorini Blue", .travel, exposure: 0.15, temperature: -250.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.12, vibrance: 0.25, shadows: (-0.006, 0.002, 0.016))
        case .parisRose: LookRecipe("Paris Rose", .travel, exposure: 0.1, temperature: 150.0, curve: [(0.0, 0.04), (0.25, 0.274), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 0.92, highlights: (0.016, 0.004, 0.008), glow: 0.1)
        case .thrillerGreen: LookRecipe("Thriller Green", .cinematic, exposure: -0.15, temperature: -150.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 0.75, shadows: (-0.004, 0.012, 0.004), highlights: (0.0, 0.01, 0.0))
        case .pastelSymmetry: LookRecipe("Pastel Symmetry", .cinematic, exposure: 0.1, temperature: 200.0, curve: [(0.0, 0.05), (0.25, 0.28), (0.5, 0.51), (0.75, 0.76), (1.0, 0.96)], saturation: 0.95, shadows: (0.008, 0.002, 0.004), highlights: (0.014, 0.01, 0.004))
        case .sunKissed: LookRecipe("Sun-Kissed", .portrait, temperature: 400.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.05, vibrance: 0.15, highlights: (0.018, 0.01, -0.004), glow: 0.15)
        case .concrete: LookRecipe("Concrete", .street, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 0.75, shadows: (-0.004, 0.0, 0.008), clarity: 0.25)
        case .subway: LookRecipe("Subway", .street, exposure: -0.1, temperature: -250.0, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 0.85, shadows: (-0.006, 0.006, 0.01))
        case .skateDay: LookRecipe("Skate Day", .street, temperature: 150.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.1, highlights: (0.012, 0.008, -0.004), clarity: 0.15)
        case .rooftop: LookRecipe("Rooftop", .street, temperature: -100.0, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 0.95, shadows: (-0.006, 0.0, 0.012), highlights: (0.01, 0.006, 0.0))
        case .graffiti: LookRecipe("Graffiti", .street, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.25, vibrance: 0.2, clarity: 0.2)
        case .cityGrey: LookRecipe("City Grey", .street, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 0.55, shadows: (-0.002, 0.0, 0.006))
        case .sodiumLight: LookRecipe("Sodium Light", .street, temperature: 500.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], highlights: (0.02, 0.01, -0.012))
        case .raincoat: LookRecipe("Raincoat", .street, exposure: -0.1, temperature: -400.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 0.8, shadows: (-0.006, 0.004, 0.014))
        case .streetNoir: LookRecipe("Street Noir", .street, mono: (0.2126, 0.7152, 0.0722), curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], clarity: 0.3)
        case .candid: LookRecipe("Candid", .street, temperature: 100.0, curve: [(0.0, 0.02), (0.25, 0.262), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.95, clarity: 0.1)
        case .neonPink: LookRecipe("Neon Pink", .neon, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.25, shadows: (0.014, -0.006, 0.018), highlights: (0.03, 0.0, 0.02), glow: 0.15)
        case .electricBlue: LookRecipe("Electric Blue", .neon, temperature: -500.0, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.25, shadows: (-0.01, 0.0, 0.03), glow: 0.15)
        case .laserLime: LookRecipe("Laser Lime", .neon, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.2, shadows: (-0.004, 0.016, 0.0), highlights: (0.006, 0.02, -0.006))
        case .clubPurple: LookRecipe("Club Purple", .neon, exposure: -0.1, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.2, shadows: (0.012, -0.008, 0.03), highlights: (0.016, 0.0, 0.022))
        case .arcade: LookRecipe("Arcade", .neon, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.35, vibrance: 0.2, shadows: (0.004, 0.0, 0.02), highlights: (0.024, 0.006, 0.0), glow: 0.12)
        case .miami: LookRecipe("Miami", .neon, temperature: 150.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.2, shadows: (-0.01, 0.01, 0.02), highlights: (0.03, 0.006, 0.012))
        case .uvParty: LookRecipe("UV Party", .neon, exposure: -0.15, temperature: -300.0, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.3, shadows: (0.01, -0.008, 0.035), glow: 0.2)
        case .hotRed: LookRecipe("Hot Red", .neon, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.25, shadows: (0.008, -0.004, 0.0), highlights: (0.03, -0.004, 0.0))
        case .cyberCyan: LookRecipe("Cyber Cyan", .neon, temperature: -300.0, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.2, shadows: (-0.012, 0.012, 0.02), highlights: (-0.004, 0.016, 0.016))
        case .afterHours: LookRecipe("After Hours", .neon, exposure: -0.2, curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)], saturation: 1.1, shadows: (0.006, -0.004, 0.022), highlights: (0.024, 0.008, 0.004), glow: 0.15)
        case .cottonCandy: LookRecipe("Cotton Candy", .pastel, exposure: 0.2, curve: [(0.0, 0.06), (0.25, 0.286), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.9, shadows: (0.006, -0.002, 0.012), highlights: (0.014, 0.004, 0.012))
        case .babyBlue: LookRecipe("Baby Blue", .pastel, exposure: 0.2, temperature: -300.0, curve: [(0.0, 0.06), (0.25, 0.286), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.85, shadows: (-0.004, 0.002, 0.014))
        case .mintCream: LookRecipe("Mint Cream", .pastel, exposure: 0.2, curve: [(0.0, 0.06), (0.25, 0.286), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.85, shadows: (-0.004, 0.01, 0.006), highlights: (0.006, 0.01, 0.004))
        case .lilac: LookRecipe("Lilac", .pastel, exposure: 0.15, curve: [(0.0, 0.06), (0.25, 0.286), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 0.85, shadows: (0.006, -0.002, 0.016), highlights: (0.01, 0.002, 0.014))
        case .peachFuzz: LookRecipe("Peach Fuzz", .pastel, exposure: 0.15, temperature: 250.0, curve: [(0.0, 0.05), (0.25, 0.28), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.9, highlights: (0.016, 0.008, 0.004))
        case .lemonade: LookRecipe("Lemonade", .pastel, exposure: 0.2, temperature: 200.0, curve: [(0.0, 0.05), (0.25, 0.28), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.9, highlights: (0.012, 0.012, -0.004))
        case .cloudy: LookRecipe("Cloudy", .pastel, exposure: 0.2, curve: [(0.0, 0.08), (0.25, 0.298), (0.5, 0.51), (0.75, 0.76), (1.0, 0.96)], saturation: 0.7)
        case .blush: LookRecipe("Blush", .pastel, exposure: 0.1, temperature: 100.0, curve: [(0.0, 0.05), (0.25, 0.28), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 0.9, highlights: (0.016, 0.004, 0.008))
        case .seaGlass: LookRecipe("Sea Glass", .pastel, exposure: 0.15, temperature: -200.0, curve: [(0.0, 0.06), (0.25, 0.286), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 0.85, shadows: (-0.006, 0.008, 0.008))
        case .dreamy: LookRecipe("Dreamy", .pastel, exposure: 0.2, curve: [(0.0, 0.06), (0.25, 0.286), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.9, glow: 0.25)
        case .terracotta: LookRecipe("Terracotta", .earth, temperature: 400.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 0.95, shadows: (0.006, 0.0, -0.004), highlights: (0.018, 0.006, -0.008))
        case .olive: LookRecipe("Olive", .earth, temperature: 150.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 0.85, shadows: (0.0, 0.008, -0.004), highlights: (0.008, 0.01, -0.006))
        case .sandstone: LookRecipe("Sandstone", .earth, exposure: 0.1, temperature: 350.0, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 0.85, highlights: (0.014, 0.01, -0.006))
        case .moss: LookRecipe("Moss", .earth, exposure: -0.1, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 0.9, shadows: (-0.002, 0.01, 0.0))
        case .clay: LookRecipe("Clay", .earth, temperature: 300.0, curve: [(0.0, 0.04), (0.25, 0.274), (0.5, 0.51), (0.75, 0.76), (1.0, 0.96)], saturation: 0.8, highlights: (0.016, 0.006, -0.002))
        case .cedar: LookRecipe("Cedar", .earth, exposure: -0.1, temperature: 450.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 0.95, highlights: (0.016, 0.008, -0.01))
        case .harvest: LookRecipe("Harvest", .earth, temperature: 500.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 1.08, highlights: (0.02, 0.012, -0.012))
        case .canyon: LookRecipe("Canyon", .earth, temperature: 550.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.05, shadows: (0.006, -0.002, 0.004), highlights: (0.022, 0.006, -0.012))
        case .linen: LookRecipe("Linen", .earth, exposure: 0.15, temperature: 200.0, curve: [(0.0, 0.05), (0.25, 0.28), (0.5, 0.51), (0.75, 0.76), (1.0, 0.97)], saturation: 0.8)
        case .coffee: LookRecipe("Coffee", .earth, exposure: -0.1, temperature: 350.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 0.75, shadows: (0.006, 0.002, -0.004), highlights: (0.012, 0.006, -0.004))
        case .velvet: LookRecipe("Velvet", .lux, exposure: -0.05, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.05, shadows: (0.006, -0.002, 0.008), highlights: (0.012, 0.006, 0.002), glow: 0.08)
        case .champagne: LookRecipe("Champagne", .lux, exposure: 0.1, temperature: 250.0, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 0.95, highlights: (0.016, 0.012, 0.0), glow: 0.1)
        case .ivory: LookRecipe("Ivory", .lux, exposure: 0.15, temperature: 150.0, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.88, highlights: (0.01, 0.008, 0.002))
        case .onyx: LookRecipe("Onyx", .lux, mono: (0.2126, 0.7152, 0.0722), curve: [(0.0, 0.0), (0.25, 0.19), (0.5, 0.5), (0.75, 0.82), (1.0, 1.0)])
        case .pearl: LookRecipe("Pearl", .lux, exposure: 0.15, curve: [(0.0, 0.03), (0.25, 0.268), (0.5, 0.51), (0.75, 0.76), (1.0, 0.98)], saturation: 0.85, highlights: (0.006, 0.006, 0.01), glow: 0.12)
        case .bordeaux: LookRecipe("Bordeaux", .lux, exposure: -0.1, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], shadows: (0.01, -0.004, 0.0), highlights: (0.012, 0.0, 0.004))
        case .sapphire: LookRecipe("Sapphire", .lux, temperature: -250.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.1, shadows: (-0.008, 0.0, 0.02))
        case .goldLeaf: LookRecipe("Gold Leaf", .lux, temperature: 400.0, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.05, highlights: (0.022, 0.016, -0.008), glow: 0.1)
        case .silk: LookRecipe("Silk", .lux, exposure: 0.1, curve: [(0.0, 0.01), (0.25, 0.235), (0.5, 0.5), (0.75, 0.775), (1.0, 0.99)], saturation: 0.95, highlights: (0.008, 0.004, 0.006), glow: 0.15)
        case .magazine: LookRecipe("Magazine", .lux, curve: [(0.0, 0.0), (0.25, 0.215), (0.5, 0.5), (0.75, 0.795), (1.0, 1.0)], saturation: 1.08, vibrance: 0.15, clarity: 0.2)
        default: nil
        }
    }
}
