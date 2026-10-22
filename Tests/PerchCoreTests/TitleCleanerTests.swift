import Testing
import PerchCore

@Suite struct TitleCleanerTests {
    @Test(arguments: [
        ("π > \u{F0219} DOCS: Inspect the sample data page", "DOCS: Inspect the sample data page"),
        ("π > Read notes, check API updates", "Read notes, check API updates"),
        ("π > 讨论 demo 项目的配置方式", "讨论 demo 项目的配置方式"),
        ("π >  \u{F408} STAR: Star a GitHub repo", "STAR: Star a GitHub repo"),
        ("π > \u{F06B0} UPD: Review the web UI update plan", "UPD: Review the web UI update plan"),
        ("π ⠼ 讨论 demo 项目的配置方式", "讨论 demo 项目的配置方式"),
        ("Perch 应用图标与布局", "Perch 应用图标与布局")
    ])
    func realTitles(_ title: String, _ expected: String) {
        #expect(TitleCleaner.clean(title) == expected)
        #expect(TitleCleaner.clean(TitleCleaner.clean(title)) == TitleCleaner.clean(title))
    }

    @Test(arguments: [
        ("π Notes", "Notes"),
        ("> Notes", "Notes"),
        ("⠼ Notes", "Notes"),
        ("\u{2800} Notes", "Notes"),
        ("\u{28FF} Notes", "Notes"),
        ("\u{F408}\u{F0219}\u{100000} Notes", "Notes"),
        ("\u{E000} \u{F8FF} \u{F0000} \u{FFFFD} \u{10FFFD} Notes", "Notes"),
        ("📄\u{FE0F} Notes", "Notes"),
        (" \tπ \n> \t\u{F408} \u{F0219} Notes \n", "Notes"),
        ("Fix > parser", "Fix > parser"),
        ("Add π support", "Add π support"),
        ("Keep \u{F0219} icon", "Keep \u{F0219} icon"),
        ("Keep ⠼ and 📄\u{FE0F} symbols", "Keep ⠼ and 📄\u{FE0F} symbols"),
        ("123 tasks", "123 tasks"),
        ("讨论配置", "讨论配置"),
        ("[task] Notes", "[task] Notes"),
        ("(task) Notes", "(task) Notes"),
        ("# Notes", "# Notes"),
        ("- Notes", "- Notes"),
        ("πr² area", "πr² area"),
        ("DOCS: Notes", "DOCS: Notes"),
        (" \tPlain title \n", "Plain title"),
        ("π >", "π >"),
        (" \tπ ⠼ \u{F0219} \n", "π ⠼ \u{F0219}"),
        (" \t\n", ""),
        ("", "")
    ])
    func prefixRulesAndPreservation(_ title: String, _ expected: String) {
        #expect(TitleCleaner.clean(title) == expected)
        #expect(TitleCleaner.clean(TitleCleaner.clean(title)) == TitleCleaner.clean(title))
    }
}
