import Testing
@testable import PerchApp

@Suite struct AgentIconTests {
    @Test(arguments: [
        ("Claude", "claudecode"), ("claude", "claudecode"), ("CLAUDE", "claudecode"),
        ("Codex", "codex"), ("codex", "codex"), ("CODEX", "codex"),
        ("OMP", "omp"), ("omp", "omp"), ("OmP", "omp"),
        ("OpenCode", "opencode"), ("opencode", "opencode"), ("OPENCODE", "opencode"),
        ("pi", "pi"), ("PI", "pi")
    ])
    func knownAgentNamesIgnoreCase(_ label: String, _ expected: String) {
        #expect(AgentIcon.name(for: label) == expected)
    }

    @Test(arguments: ["future-agent", ""])
    func unknownAgentNamesHaveNoIcon(_ label: String) {
        #expect(AgentIcon.name(for: label) == nil)
    }
}
