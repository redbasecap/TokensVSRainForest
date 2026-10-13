# Methodik: Tokens → Strom → CO₂ → Regenwald

TokensVSRainForest zeigt eine **CO₂-Äquivalenz**: Wie viel Amazonas-Regenwald speichert so viel Kohlenstoff,
wie der Strom für deine KI-Tokens freigesetzt hat? Es wird kein Wald tatsächlich gerodet, und die Werte sind
Schätzungen mit großer Unsicherheit. Alle Konstanten stehen in
[`Sources/RainforestCore/Methodology.swift`](../Sources/RainforestCore/Methodology.swift) und sind durch Tests
festgehalten ([`MethodologyTests.swift`](../Tests/RainforestCoreTests/MethodologyTests.swift)).

## 1. Tokens zählen (nur lokal)

| Quelle | Pfad | Was gezählt wird |
| --- | --- | --- |
| Claude Code | `~/.claude/projects/**/*.jsonl`, `~/.config/claude/projects`, `$CLAUDE_CONFIG_DIR/projects` | `message.usage` von `assistant`-Zeilen: `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`. Dedupliziert über `message.id` + `requestId`, der letzte Streaming-Chunk zählt (wie CodexBar). |
| Codex CLI | `$CODEX_HOME` bzw. `~/.codex/sessions`, `~/.codex/archived_sessions` | `event_msg` / `token_count`: `last_token_usage` pro Anfrage. Wiederholte Summen werden übersprungen, Events aus geforkten Rollouts werden über Zeitstempel + Summe dedupliziert. `input_tokens` enthält schon die gecachten Tokens, `output_tokens` schon die Reasoning-Tokens. |

Es gibt keine Netzwerkanfragen, keinen Schlüsselbund und keine Cookies. Nutzung über claude.ai, ChatGPT oder
deren Apps erscheint nicht in diesen Logs und wird daher **nicht** gezählt.

## 2. Strom pro Token

Grundlage: **Jegham et al. (2025), „How Hungry is AI?“, arXiv:2505.09598v6, Tabelle 4**. Dort steht der Strom
pro Anfrage (inklusive PUE) für drei Prompt-Größen:

| Modell (Cloud) | 100 in / 300 out | 1 000 in / 1 000 out | 10 000 in / 1 500 out |
| --- | --- | --- | --- |
| Claude 3.7 Sonnet (AWS) | 0,950 Wh | 2,989 Wh | 5,671 Wh |
| GPT-4o, Mar '25 (Azure) | 0,423 Wh | 1,215 Wh | 2,875 Wh |

Durch diese drei Punkte wird exakt das Modell `E = c · Anfragen + a · Input + b · Output` gelegt:

| | c (Wh/Anfrage) | a (mWh/Input-Token) | b (mWh/Output-Token) |
| --- | --- | --- | --- |
| Claude (für alle Claude-Modelle) | 0,118 | 0,147 | 2,724 |
| Codex (für alle Codex-Modelle) | 0,121 | 0,131 | 0,963 |

Die vier Token-Klassen werden so gewichtet:

* **Frischer Input** und **Cache-Write**: `a` pro Token (der Prefill wird neu berechnet).
* **Cache-Read**: `0,1 · a` pro Token. **Das ist eine Annahme.** Cache-Treffer überspringen den Prefill. Eine
  öffentliche Energiemessung dazu gibt es nicht, deshalb dient das Preisverhältnis von Anthropic als Näherung
  (Cache-Read = 0,1 × Basis-Input-Preis, [Doku](https://docs.claude.com/en/docs/build-with-claude/prompt-caching)).
  Bei Claude Code machen Cache-Reads oft über 95 % der Tokens aus. Dieser Faktor ist deshalb die größte
  Stellschraube.
* **Output**: `b` pro Token, inklusive Thinking/Reasoning.

Plausibilitätsprüfung:

* Epoch AI (2025) schätzt ≈ 0,3 Wh für eine GPT-4o-Anfrage mit 500 Output-Tokens, also ≈ 0,6 mWh pro Token
  ([Quelle](https://epoch.ai/gradient-updates/how-much-energy-does-chatgpt-use)).
* Google misst 0,24 Wh für einen mittleren Gemini-Apps-Prompt (Elsworth et al. 2025, arXiv:2508.15734).
* Die Jegham-Werte liegen eher am oberen Ende.

Grenzen:

* Für Claude 4/5, GPT-5 oder neuere Modelle gibt es keine öffentlichen Werte pro Token. Deshalb werden die
  Werte von Sonnet 3.7 bzw. GPT-4o verwendet.
* Größere Modelle (z. B. Opus) brauchen vermutlich mehr Strom. Das ist bewusst nicht mit einem erfundenen
  Faktor hochskaliert.
* Der Fit deckt nur Inputs bis 10 000 Tokens ab. In Claude Code liegen oft 100 000–200 000 Tokens (meist aus dem
  Cache) im Kontext. Der Input-Koeffizient wird dort also linear weit über die Messdaten hinaus verlängert.

## 3. CO₂ pro kWh

| Einstellung | Wert | Quelle |
| --- | --- | --- |
| Rechenzentrum (Standard) | Claude/AWS 0,287 kg CO₂e/kWh, Codex/Azure 0,35 kg CO₂e/kWh | Jegham et al. 2025, Tabelle 1 |
| Weltdurchschnitt | 0,458 kg CO₂e/kWh (2025) | [Ember, Global Electricity Review 2026](https://ember-energy.org/latest-insights/global-electricity-review-2026/) |

Die Energiewerte enthalten den PUE bereits. Er wird deshalb nicht noch einmal aufgeschlagen.

## 4. CO₂ → Regenwald

| Schritt | Wert | Quelle |
| --- | --- | --- |
| Oberirdische Biomasse, tropischer Regenwald, Nord- & Südamerika, Primärwald | 307,1 t Trockenmasse/ha (SD 104,9) | [IPCC 2019 Refinement, Vol. 4 Kap. 4, Tabelle 4.7](https://www.ipcc-nggip.iges.or.jp/public/2019rf/pdf/4_Volume4/19R_V4_Ch04_Forest%20Land.pdf) |
| Kohlenstoffanteil tropischer Biomasse | 0,47 t C / t TM (0,44–0,49) | [IPCC 2006, Vol. 4 Kap. 4, Tabelle 4.3](https://www.ipcc-nggip.iges.or.jp/public/2006gl/pdf/4_Volume4/V4_04_Ch4_Forest_Land.pdf) (im 2019 Refinement unverändert) |
| C → CO₂ | × 44/12 | Molmassen |
| **= CO₂ pro Fläche** | **529 t CO₂/ha = 52,9 kg CO₂/m²** | |
| Bäume pro Hektar (≥ 10 cm Stammdurchmesser) | 565 (Median) | [ter Steege et al. 2013, Science 342](https://doi.org/10.1126/science.1243092) |
| **= CO₂ pro Baum** | **≈ 937 kg** | |

Die Wurzelbiomasse (IPCC Tab. 4.4: R = 0,221) ist **nicht** eingerechnet:

* Bei einem Brand wird sofort vor allem die oberirdische Biomasse freigesetzt. Das passt zum Bild „verbrannt“.
* Das ist **nicht** die vorsichtige Wahl. Mit Wurzeln speichert ein Baum ≈ 1 144 kg CO₂
  (307,1 × 1,221 × 0,47 × 44/12 ÷ 565). Damit ergeben sich etwa 18 % weniger Bäume pro kg CO₂.

## 5. Pixel-Einheiten

Der Pixel-Baum der App hat 40 Blöcke (`TreeLayout`, per Test abgesichert), jeder Block hat eine Textur aus
16 × 16 Pixeln, wie in Minecraft:

* 1 Baum ≈ 937 kg CO₂
* 1 Block ≈ 23,4 kg CO₂
* 1 Pixel ≈ 91,5 g CO₂

Die Szene zoomt je nach Menge:

* unter einem Block: Zoom auf einen einzelnen Blatt-Block
* unter einem Baum: ein ganzer Baum
* darüber: ein Wald mit bis zu 18 Baum-Symbolen

## 6. Beispielrechnung (als Test festgehalten)

Claude Code, ein Tag mit:

* 2 000 Anfragen
* 10 000 frischen Input-Tokens
* 1 000 000 Cache-Writes
* 50 000 000 Cache-Reads
* 500 000 Output-Tokens

Rechnung:

```
2 000 × 0,118 Wh                                   =   236 Wh
0,147 mWh × (10 000 + 1 000 000 + 0,1 × 50 000 000) =   881 Wh
2,724 mWh × 500 000                                = 1 362 Wh
                                                   ≈ 2,48 kWh × 0,287 kg/kWh ≈ 0,71 kg CO₂e
                                                   ≈ 134 cm² Regenwald ≈ 7,8 Pixel ≈ 0,00076 Bäume
```

## Nicht enthalten

* Training der Modelle
* Herstellung der Hardware (Scope 3)
* Wasserverbrauch
* Netzwerk-Übertragung
* der eigene Rechner
* Leerlauf-Kapazität über das hinaus, was Jegham et al. modellieren
