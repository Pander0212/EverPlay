# Research and licensing decisions

Inspection date: **2026-10-20**. Native HTTPS Git access succeeded. Each listed repository was shallow-fetched; README/license/build manifests and relevant source-tree paths were inspected. Dates below are the **latest observed commit timestamp**, not a claim that the project is actively maintained or that every release works. Shallow history does not establish the last substantive code change beyond the identified commit. Remote tag references were queried separately; tag presence does not verify GitHub release assets or iOS compilation. GitHub API requests were initially denied by the environment proxy (CONNECT 403). A later permitted API inspection verified archive status and published release metadata; the results are recorded below and in `RESEARCH_METADATA.json`. Release binaries were not downloaded or executed, and upstream CI success is not implied. No third-party app/interpreter was executed.

## [mateo-m/empo-app](https://github.com/mateo-m/empo-app)

- **License:** GPLv3 code; documentation CC BY-NC-SA 4.0.
- **Observed activity:** [276d5e7358f4](https://github.com/mateo-m/empo-app/commit/276d5e7358f47813e5a9f9086060204f45db30fb), 2026-10-20T12:51:44+02:00; `chore(mkxp): use engine v8 (#202)`.
- **Release evidence:** v0.7.3 observed.
- **Architecture/dependencies:** SwiftUI/UIKit launcher with packaged mkxp-z-apple-mobile, multiple Ruby versions, PSDK native runtimes and a web view for MV/MZ. Source layout and iOS project.yml inspected. Declares iOS 26+ and pre-release status.
- **Engines/functionality:** XP/VX/VX Ace, PSDK, MV/MZ (upstream claims, not reproduced here).
- **iOS feasibility/risks:** Native iOS project exists; native dependencies and engine versions are substantial. Multi-session/native state and Windows APIs remain compatibility risks.
- **Decision/reusability:** Study architecture and mobile engine forks. Do not copy GPL code or NC documentation into the MIT foundation; any future integration needs a GPL-compatible distribution decision.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-10-20T13:23:32Z. First listed published release: [v0.7.4](https://github.com/mateo-m/empo-app/releases/tag/v0.7.4), published 2026-10-20T12:25:09Z, prerelease=false, 1 attached assets.

## [2p1endid/rrppgo](https://github.com/2p1endid/rrppgo)

- **License:** MIT (LICENSE verified).
- **Observed activity:** [98390e03e2b7](https://github.com/2p1endid/rrppgo/commit/98390e03e2b7585e7dea8aa7f4cc087a5c69af17), 2026-08-15T02:28:13+08:00; `Merge remote-tracking branch 'origin/main'`.
- **Release evidence:** v0.1.1 observed.
- **Architecture/dependencies:** Swift iOS 17+ app, WKWebView/local HTTP resource server, ZIPFoundation and XcodeGen. Read GameWebView, LocalGameHTTPServer and SafeZIPExtractor implementation. JS tooling is for portable checks.
- **Engines/functionality:** MV/MZ web deployments.
- **iOS feasibility/risks:** Closest architectural reference for this foundation. Source exists; upstream unsigned IPA descriptions are not signing evidence. The inspected server binds a general TCP listener; EverPlay instead explicitly binds loopback and validates Host/token.
- **Decision/reusability:** Study; original implementation here, with independently tested import/router rules. Prefer a narrow Swift stack over a whole-launcher fork.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-08-20T09:42:31Z. First listed published release: [v0.1.1](https://github.com/2p1endid/rrppgo/releases/tag/v0.1.1), published 2026-08-14T18:34:28Z, prerelease=false, 1 attached assets.

## [yoimerdr/ludens](https://github.com/yoimerdr/ludens)

- **License:** Apache-2.0 (LICENSE verified).
- **Observed activity:** [45e76a9210b1](https://github.com/yoimerdr/ludens/commit/45e76a9210b121f067cb7918877ef71ef5451f94), 2026-07-19T00:55:04-05:00; `release: v0.4.0 (#6)`.
- **Release evidence:** 0.4.0 observed.
- **Architecture/dependencies:** Kotlin Compose Multiplatform WebView wrapper with Gradle builds and platform-specific WebView helpers. Repository docs explicitly say iOS build configuration is incomplete/template-based; Android is the documented focus.
- **Engines/functionality:** MV/MZ web exports.
- **iOS feasibility/risks:** Browser patterns are relevant, but porting Kotlin UI would add a second application stack. Saves rely on browser storage; it is not a native save manager.
- **Decision/reusability:** Study mobile/web compatibility ideas; do not integrate as the SwiftUI app base.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-08-01T21:35:08Z. First listed published release: [0.4.0](https://github.com/yoimerdr/ludens/releases/tag/0.4.0), published 2026-07-19T06:11:03Z, prerelease=false, 1 attached assets.

## [EasyRPG/Player](https://github.com/EasyRPG/Player)

- **License:** GPLv3 (COPYING and README verified; dependencies have additional licenses).
- **Observed activity:** [096c004def98](https://github.com/EasyRPG/Player/commit/096c004def987f3545198304b1b7a8352f284a50), 2026-10-19T19:52:03+02:00; `Merge pull request #3500 from EasyRPG-NewFeatures/maniacs/setPictureID`.
- **Release evidence:** 0.8.1.1 observed.
- **Architecture/dependencies:** C++ interpreter; liblcf parses LCF game data, SDL2 handles platform I/O, optional audio/fonts/codecs. CMake and dependency options inspected.
- **Engines/functionality:** RPG Maker 2000/2003 and EasyRPG; not XP/VX/VX Ace.
- **iOS feasibility/risks:** Potential mobile interpreter, requiring a dedicated native build/input/audio lifecycle and license audit. This task did not compile an iOS EasyRPG build.
- **Decision/reusability:** Preferred proven interpreter to evaluate for 2000/2003 later. No linking now. A combined distributed work may need GPLv3 source/install obligations and distribution-policy review.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-10-19T17:52:03Z. First listed published release: [0.8.1.1](https://github.com/EasyRPG/Player/releases/tag/0.8.1.1), published 2025-06-02T11:17:44Z, prerelease=false, 0 attached assets.

## [NaniteCrafter/rpgmaker-translator4](https://github.com/NaniteCrafter/rpgmaker-translator4)

- **License:** Modified Business Source License 1.1: noncommercial use grant, Change Date/Change License set to None.
- **Observed activity:** [ffc78f5681aa](https://github.com/NaniteCrafter/rpgmaker-translator4/commit/ffc78f5681aa4932b887cc39e4f0b2f653dce601), 2026-03-25T09:27:44-04:00; `Fix split-words undoing compound fixes: swap execution order`.
- **Release evidence:** No remote tags observed.
- **Architecture/dependencies:** Python desktop translation tool with engine-specific parsing and cloud/local LLM handling, bulk resource rewriting, OCR-related options and RPG Maker workspace support. README and requirements tree inspected.
- **Engines/functionality:** Claims MV/MZ/VX Ace/2000/2003, Ren’Py and several other text formats.
- **iOS feasibility/risks:** Not a native iOS runtime; desktop filesystem/tooling assumptions. License text is source-available, not an unrestricted open-source grant.
- **Decision/reusability:** Reject code integration. Study publicly described requirements only; do not adopt its noncommercial restrictions into the MIT foundation. No provider/free-tier claims accepted without separate verification.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-03-25T13:27:46Z. The releases API returned no published releases; Git tags, where present, are listed separately above.

## [nt7011/RPG-Maker-Live-Translator](https://github.com/nt7011/RPG-Maker-Live-Translator)

- **License:** AGPLv3 (LICENSE verified).
- **Observed activity:** [518f543e5952](https://github.com/nt7011/RPG-Maker-Live-Translator/commit/518f543e595219468104aa4fde3ecc69f847f1f5), 2026-09-24T04:52:12+09:00; `release: dist-5.1.0b0`.
- **Release evidence:** v5.1.0b0 observed.
- **Architecture/dependencies:** JavaScript runtime drawing/text hooks and look-ahead translation. Desktop NW.js installation; local LLM integration via llamafile/llama.cpp. Inspected src tree and runtime/provider layout.
- **Engines/functionality:** MV/MZ.
- **iOS feasibility/risks:** NW.js and locally executed model backends are not drop-in WKWebView/iOS dependencies; low-level bitmap hooks depend on plugins/engine versions.
- **Decision/reusability:** Study asynchronous text/rendering constraints. No code copied. An adopted AGPL component needs copyleft/source-offer review, including applicable remote-network interaction duties.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-09-23T20:03:00Z. First listed published release: [v5.1.0b0](https://github.com/nt7011/RPG-Maker-Live-Translator/releases/tag/v5.1.0b0), published 2026-09-23T19:54:19Z, prerelease=true, 2 attached assets.

## [JaimeDevCode/RPGMakerTranslator](https://github.com/JaimeDevCode/RPGMakerTranslator)

- **License:** MIT (LICENSE verified).
- **Observed activity:** [5fe39257427b](https://github.com/JaimeDevCode/RPGMakerTranslator/commit/5fe39257427b27efa9d38eff72512c722d7c54d1), 2026-03-02T13:34:24+01:00; `feat: Hendrix_Localization CSV export, Show Picture/Movie extraction, multi-line context`.
- **Release evidence:** No remote tags observed.
- **Architecture/dependencies:** Python text and image/OCR translation, CSV export/import, deep-translator/python-dotenv with optional Pillow/OpenCV/easyocr and torch/transformers/Marian models.
- **Engines/functionality:** MV/MZ JSON and associated images.
- **iOS feasibility/risks:** Useful extraction ideas, but Python ML/OCR installation is not a small iOS dependency. In-place file changes require backup/overlay redesign.
- **Decision/reusability:** Study first; a focused extraction port may be considered with attribution and tests. Do not run auto-installing optional model dependencies in the foundation.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-03-02T12:34:30Z. The releases API returned no published releases; Git tags, where present, are listed separately above.

## [paradoxie/saveeditor](https://github.com/paradoxie/saveeditor)

- **License:** README/package presentation claims MIT; no root LICENSE found in the inspected tree.
- **Observed activity:** [67c47f217b4e](https://github.com/paradoxie/saveeditor/commit/67c47f217b4e683408fda17adf627dfdbdaed783), 2026-08-31T18:09:11+08:00; `Document NRBF save support`.
- **Release evidence:** No remote tags observed.
- **Architecture/dependencies:** Astro/React browser editor with JS/WASM parsers, local processing and parser fidelity tests. README notes analytics/ads on the website. Formats include RPG Maker and experimental Ren’Py; unrelated engines are outside EverPlay scope.
- **Engines/functionality:** Selected save formats, not game execution.
- **iOS feasibility/risks:** Browser parsers may be portable, but compressed/serialized save fidelity must be proven. License grant is not sufficiently evidenced by a README badge alone.
- **Decision/reusability:** Study format/test coverage; defer copying until the missing license grant is resolved. Do not embed the hosted site or its analytics in the app.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-08-31T10:09:15Z. The releases API returned no published releases; Git tags, where present, are listed separately above.

## [paramonos/RPG-Maker-MV-MZ-Cheat-UI-Plugin](https://github.com/paramonos/RPG-Maker-MV-MZ-Cheat-UI-Plugin)

- **License:** MIT (LICENSE verified).
- **Observed activity:** [4ac67fd469e9](https://github.com/paramonos/RPG-Maker-MV-MZ-Cheat-UI-Plugin/commit/4ac67fd469e9890fbe8298fffad6e9d92354e71b), 2025-04-28T01:49:47+09:00; `Update README_ko-kr.md`.
- **Release evidence:** v1.0.3 observed.
- **Architecture/dependencies:** JavaScript cheat GUI packaged for MV/MZ; documentation discusses NW.js versions and installation in game directories.
- **Engines/functionality:** MV/MZ single-player state.
- **iOS feasibility/risks:** Engine access patterns are relevant, but desktop UI/Node assumptions and plugin conflicts need verification on WKWebView. Last observed tip is a documentation update, not proof of active code maintenance.
- **Decision/reusability:** Study and potentially port selected compatible functionality later with license notices. Require opt-in, game-specific capabilities and save backups before activation.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2025-04-27T16:49:48Z. First listed published release: [v1.0.3](https://github.com/paramonos/RPG-Maker-MV-MZ-Cheat-UI-Plugin/releases/tag/v1.0.3), published 2022-06-05T13:08:54Z, prerelease=false, 2 attached assets.

## [modelcontextprotocol/typescript-sdk](https://github.com/modelcontextprotocol/typescript-sdk)

- **License:** Licensing transition: new contributions Apache-2.0, existing code MIT; retain both applicable grants/notices.
- **Observed activity:** [9bc40e903fde](https://github.com/modelcontextprotocol/typescript-sdk/commit/9bc40e903fde15534ec06ff4c1347d47000dbe16), 2026-10-13T13:11:15+01:00; `Docs/migration skill (#2968)`.
- **Release evidence:** v2.3.1 observed; root package metadata still says 2.0.0-alpha.0.
- **Architecture/dependencies:** TypeScript monorepo with server/client packages, optional HTTP framework middleware, stdio/HTTP transports, auth helpers and schemas. Main README describes stable v2 and the 2026-07-28 spec; root version is not a reliable published release indicator. pnpm 10.26.1, Node >=20.
- **Engines/functionality:** Engine-independent developer tooling.
- **iOS feasibility/risks:** Run on a desktop companion, not as a persistent iOS background MCP service. Tool schemas do not themselves enforce per-game filesystem or installation permissions.
- **Decision/reusability:** Integrate an exact verified release in milestone 5. No SDK is installed in this foundation; compare published package metadata and license at implementation time.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-10-20T14:33:45Z. First listed published release: [v2.3.1](https://github.com/modelcontextprotocol/typescript-sdk/releases/tag/v2.3.1), published 2026-10-05T11:54:56Z, prerelease=false, 0 attached assets.

## [weichsel/ZIPFoundation](https://github.com/weichsel/ZIPFoundation)

- **License:** MIT (LICENSE at pinned dependency verified).
- **Observed activity:** [e7a17d57c583](https://github.com/weichsel/ZIPFoundation/commit/e7a17d57c583067eaa6659cd6d9521265b7664e9), 2026-09-12T10:20:40+02:00; `Merge pull request #390 from weichsel/chore/test-runners`.
- **Release evidence:** 0.9.20 pinned (commit 22787ffb59de99e5dc1fbfe80b19c97a904ad48d).
- **Architecture/dependencies:** Native Swift ZIP reader/writer; Apple Compression on Apple platforms, zlib on Linux. Inspected Package.swift, Entry and Archive+Reading APIs. The extract API returns CRC; caller must compare it to the entry checksum.
- **Engines/functionality:** Archive infrastructure, engine-independent.
- **iOS feasibility/risks:** SPM/iOS compatible with no additional third-party runtime dependency on Apple. Requires caller-side extraction policy, path/size validation and cancellation.
- **Decision/reusability:** Integrate 0.9.20 with explicit CRC comparison, budget checks and hostile-package tests. Actual Linux extraction tests pass.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-09-12T08:20:42Z. First listed published release: [0.9.20](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.20), published 2025-09-24T18:44:49Z, prerelease=false, 0 attached assets.

## [mkxp-z/mkxp-z](https://github.com/mkxp-z/mkxp-z)

- **License:** GPLv2+; README says default OpenSSL linkage implies GPLv3-compatible distribution.
- **Observed activity:** [37a04d144134](https://github.com/mkxp-z/mkxp-z/commit/37a04d14413454551a7b6aadbb4e93e67168accb), 2026-10-03T08:32:53Z; `Merge pull request #394 from white-axe/stack-size`.
- **Release evidence:** v2.4.2 observed.
- **Architecture/dependencies:** C++ RGSS reimplementation with MRI Ruby, SDL/audio/graphics dependencies and desktop compatibility shims. Upstream names Windows/Linux/macOS, not turnkey iOS.
- **Engines/functionality:** RGSS1/2/3 (XP/VX/VX Ace), with game-specific compatibility work.
- **iOS feasibility/risks:** Native library builds, multiple Ruby versions, Windows calls, executable loading and graphics backends are major risks. Empo references a mobile fork worth separate review.
- **Decision/reusability:** Study as the proven interpreter alternative to inventing RGSS. No fake adapter and no linking before license/build/runtime lifecycle validation.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-10-03T08:32:53Z. The releases API returned no published releases; Git tags, where present, are listed separately above.

## [renpy/renpy](https://github.com/renpy/renpy)

- **License:** Mostly MIT; official license documentation lists LGPL and other dependency obligations.
- **Observed activity:** [f209eb175dd8](https://github.com/renpy/renpy/commit/f209eb175dd8b2855a2fcaa536f9e4654490ed08), 2026-10-19T19:27:29-04:00; `Merge pull request #7452 from Moshibit/master`.
- **Release evidence:** Version tags observed, including 8.5.3.26051504; release asset status unverified.
- **Architecture/dependencies:** Python/Cython/C engine with SDL/media dependencies and a dedicated iOS export process. Read official sphinx/source/ios.rst and license.rst. iOS projects are version-specific and recreated after engine upgrades.
- **Engines/functionality:** Ren’Py games packaged for a compatible engine/export.
- **iOS feasibility/risks:** Official iOS export exists, but requires Xcode/signing and a known engine build. Desktop archives, compiled scripts, Python modules and saves are not universally compatible. LGPL static-link/relink obligations need review.
- **Decision/reusability:** Study official export path before designing a selected-version adapter. Do not claim arbitrary Windows games will run.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-10-20T12:14:26Z. First listed published release: [8.5.3.26051504](https://github.com/renpy/renpy/releases/tag/8.5.3.26051504), published 2026-05-16T02:09:49Z, prerelease=false, 14 attached assets.

## [godotengine/godot](https://github.com/godotengine/godot)

- **License:** MIT engine (LICENSE.txt verified); third-party components retain separate licenses.
- **Observed activity:** [469659e06173](https://github.com/godotengine/godot/commit/469659e0617345149cd1eaec2e643d61d130aa6a), 2026-10-19T15:49:30-05:00; `Merge pull request #124649 from akien-mga/ufbx-0.23.1`.
- **Release evidence:** 4.7.2-stable observed.
- **Architecture/dependencies:** C++ engine with native platform backends and versioned export/runtime resources. Source includes iOS platform, GDScript and PCK handling; native extensions are separate executable code.
- **Engines/functionality:** Godot resources for matching compatible engine builds, not arbitrary desktop executables.
- **iOS feasibility/risks:** iOS exports need signing; engine/PCK versions and GDExtensions matter. Web exports may be a smaller experiment but require WebGL/WASM/browser-feature validation.
- **Decision/reusability:** Study official runtime/export path; no native/PCK adapter until a narrow real-game fixture is proven. Web compatibility is not presumed.
- **API follow-up (2026-10-20):** not archived; repository push timestamp 2026-10-20T14:44:29Z. First listed published release: [3.6.3-stable](https://github.com/godotengine/godot/releases/tag/3.6.3-stable), published 2026-08-22T14:05:19Z, prerelease=false, 26 attached assets.

## Additional dependency decisions

The alternatives above were selected for relevance and first-party/proven implementations, not declared “better maintained” without evidence. Original Swift code plus the small ZIPFoundation dependency is appropriate for milestone 1; a native interpreter fork is not needed for HTML5.

- **Apple Swift Crypto 3.12.3:** Apache-2.0; inspected the pinned license and package manifest. Provides streaming SHA-256 and uses CryptoKit on Apple systems. Linux includes BoringSSL with its retained license. Swift ASN.1 is a pinned Apache-2.0 transitive package; its API is not used by EverPlay.
- **XcodeGen 2.44.1:** MIT; license and manifest inspected at commit `21ac9944b0ab546a07422dbed86f33dd2ebd76f8`. Build-only project generator. Its official pinned source and tracked lockfile were built successfully on Linux, and the actual project generated successfully.
- **Playwright 1.64.1:** Apache-2.0, development-only browser checks. Exact npm dependency and integrity lock recorded; no install scripts were needed. Local tests use the installed Chromium. npm audit reported zero vulnerabilities at execution time, not a permanent safety guarantee.
- **GitHub Actions:** checkout v5, setup-node v5, upload-artifact v6 and cache v5.1.0 are pinned to verified upstream commit hashes. Their action metadata was checked for Node.js 24 runtime compatibility. Cache restore/save preserves the exact XcodeGen source build, including when an application test fails. No installer action receives signing secrets.

## Distribution strategy

The foundation's original code and demo are MIT. Bundled ZIPFoundation/Swift Crypto notices are retained in `App/Resources/ThirdPartyNotices.txt`. No GPL/AGPL interpreter, translator code, proprietary RPG Maker runtime or copyrighted game asset was copied into the foundation.

If a later milestone links or derives code from EasyRPG, mkxp-z or Empo, assess the combined work under the actual GPL versions and dependency licenses; do not assume a Swift protocol boundary removes copyleft. Distribution may require GPL-compatible licensing for the combined program, corresponding source/build scripts/notices, and applicable installation/relink information. Review compatibility with Apple distribution terms before promising App Store/TestFlight delivery. AGPL network-interaction obligations and Ren’Py LGPL dependencies require their own review. The noncommercial BSL translator and license-unclear saveeditor are not adopted.

## Interpreting the API follow-up

Release lists and tag lists answer different questions. The API follow-up above records the first result of `GET /repos/{owner}/{repo}/releases?per_page=1`; it is not an assertion that this tag is the highest semantic version or the preferred engine line. For example, Godot has multiple maintained release lines. Empo published v0.7.4 after the initially inspected source snapshot. Ren’Py and saveeditor both have null API license detection, but Ren’Py’s actual documented license was inspected directly; a null API field does not itself establish missing rights. The MCP SDK’s licensing transition also needs the actual license text, not GitHub’s NOASSERTION label. Original source inspection and the pinned dependency licenses remain authoritative for integration decisions.
