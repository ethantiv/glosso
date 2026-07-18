import Foundation

struct GenerateRequest: Encodable, Sendable {
    struct Options: Encodable, Sendable {
        var temperature: Double
        var numPredict: Int?

        enum CodingKeys: String, CodingKey {
            case temperature
            case numPredict = "num_predict"
        }
    }

    var model: String
    var prompt: String
    var stream: Bool
    var think: Bool
    var options: Options
    var keepAlive: String

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case stream
        case think
        case options
        case keepAlive = "keep_alive"
    }

    init(config: LLMConfig, prompt: String, stream: Bool, numPredict: Int? = nil) {
        self.model = config.model
        self.prompt = prompt
        self.stream = stream
        self.think = config.think
        self.options = Options(temperature: config.temperature, numPredict: numPredict)
        self.keepAlive = config.keepAlive
    }
}

struct GenerateChunk: Decodable, Sendable {
    var response: String?
    var done: Bool
    var doneReason: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case response
        case done
        case doneReason = "done_reason"
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response = try container.decodeIfPresent(String.self, forKey: .response)
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        doneReason = try container.decodeIfPresent(String.self, forKey: .doneReason)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}
