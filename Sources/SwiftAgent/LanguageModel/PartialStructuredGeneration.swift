import Foundation
import PartialJSONDecoder

/// Decodes a partial structured JSON stream into SwiftAgent generated content.
package func partialStructuredGeneration<Content: Generable>(
  from jsonString: String,
  as type: Content.Type = Content.self,
) -> (content: Content.PartiallyGenerated, rawContent: GeneratedContent)? {
  _ = type
  let decoder = PartialJSONDecoder()

  if let partialContent = try? decoder.decode(GeneratedContent.self, from: jsonString).value {
    let partial: Content.PartiallyGenerated? = try? .init(partialContent)
    if let partial {
      return (partial, partialContent)
    }
  }

  if let rawContent = try? GeneratedContent(json: jsonString) {
    let partial: Content.PartiallyGenerated? = try? .init(rawContent)
    if let partial {
      return (partial, rawContent)
    }
    if let complete = try? Content(rawContent) {
      return (complete.asPartiallyGenerated(), rawContent)
    }
  }

  return nil
}
