import Foundation

/// One question to ask the pediatrician, checked off once it's been asked.
struct VisitQuestion: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var isAsked = false
}

/// Questions are kept as plain text, one per line, so they read well anywhere (CSV, iCloud) and
/// sync as a single field. A question that's been asked starts with "[x] ".
enum VisitQuestions {
    private static let askedPrefix = "[x] "

    static func parse(_ text: String) -> [VisitQuestion] {
        text.split(whereSeparator: \.isNewline).compactMap { raw -> VisitQuestion? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(askedPrefix) {
                let question = String(line.dropFirst(askedPrefix.count)).trimmingCharacters(in: .whitespaces)
                return question.isEmpty ? nil : VisitQuestion(text: question, isAsked: true)
            }
            return line.isEmpty ? nil : VisitQuestion(text: line)
        }
    }

    static func serialize(_ questions: [VisitQuestion]) -> String {
        questions.compactMap { question -> String? in
            // A question is one line, so a pasted line break can't split it in two.
            let text = question.text
                .components(separatedBy: .newlines)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return question.isAsked ? askedPrefix + text : text
        }
        .joined(separator: "\n")
    }

    /// `text` with one more question at the end.
    static func appending(_ question: String, to text: String) -> String {
        serialize(parse(text) + [VisitQuestion(text: question)])
    }
}

extension Appointment {
    var questionList: [VisitQuestion] {
        get { VisitQuestions.parse(questions) }
        set { questions = VisitQuestions.serialize(newValue) }
    }
}

extension Baby {
    var pendingQuestionList: [VisitQuestion] {
        get { VisitQuestions.parse(pendingQuestions) }
        set { pendingQuestions = VisitQuestions.serialize(newValue) }
    }
}
