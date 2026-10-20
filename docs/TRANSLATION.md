# Translation — planned, not implemented

No provider is contacted and no translation settings or credential fields are exposed in the foundation. The demo deliberately contains Japanese dialogue in `dialogue.json` and `[data-translate]` DOM text as future extraction fixtures.

## Intended design

- An engine-independent async provider API accepts text, source/target language, glossary, bounded history and model. Provider results include optional token/cost metadata, rather than invented estimates.
- Live, pre-translation and hybrid coordinators share a SQLite translation memory keyed by source, language pair, provider/model, glossary and game context/version. Database migrations must precede schema changes.
- Coalesce in-flight duplicates; bound queue size/concurrency and batch sizes; support task cancellation, explicit request timeouts, bounded retries with jitter, `Retry-After`, and opt-in provider fallback.
- Protect RPG Maker escapes and placeholders before translation, then verify every protected token survives. Reject corrupt output and keep original text. Ren’Py interpolation requires its own parser, not regex-only rewriting of scripts.
- Begin with opt-in DOM text observation and MV/MZ dialogue interfaces. Canvas interception and OCR are separate experiments; neither is universal. Render the original text immediately and apply safe translated updates asynchronously.
- Store BYOK secrets only in Keychain. Never expose them to imported JavaScript, the library manifest or a mod. Show exactly which provider receives game text and require opt-in.
- Potential providers: OpenAI-compatible endpoints, OpenRouter, Gemini, DeepL; Apple Translation needs availability checks (iOS 18+ where applicable). Provider free tiers/prices have **not** been researched or promised in this milestone.

Next milestone must test deterministic provider behavior, cache hits, duplicate coalescing, language/model isolation, glossary changes, placeholder round-trips, provider errors, rate limits, cancellation and timeout. A deterministic test provider is not an actual AI integration.
