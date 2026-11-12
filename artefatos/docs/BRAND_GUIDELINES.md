# TubExtractor — Brand Guidelines & Design Tokens

## 1. Identidade e Posicionamento
- **Nome Oficial:** TubExtractor
- **Assinatura (Tagline):** Bulk YouTube Transcriptions
- **Promessa da Marca:** Produtividade sem atrito, processamento em lote e privacidade (sem conta, sem servidor do autor; o app só fala com o YouTube).

---

## 2. Paleta de Cores Oficial

| Função | Token | Hex | RGB | Uso Principal |
| :--- | :--- | :--- | :--- | :--- |
| **Primary Accent** | `--color-accent-coral` | `#FF4444` | `rgb(255, 68, 68)` | Acentos, botão de ação principal, início do gradiente |
| **Secondary Accent** | `--color-accent-peach` | `#FF7864` | `rgb(255, 120, 100)` | Estados de hover, transição do logo, badges |
| **Selection (dark)** | `--color-accent-teal` | `#5EE6C8` | `rgb(94, 230, 200)` | Modo escuro: seleção, foco, progresso, botões simples (D-01 C). Coral fica só em Buscar, Baixar ZIP e "Extractor" |
| **Background Dark** | `--color-bg-base` | `#121418` | `rgb(18, 20, 24)` | Fundo da aplicação / tema escuro nativo |
| **Surface Dark** | `--color-surface-card` | `#1C1F26` | `rgb(28, 31, 38)` | Cards de vídeos, painéis de exportação |
| **Surface Border** | `--color-border-subtle` | `#2D333F` | `rgb(45, 51, 63)` | Divisores, bordas de inputs e caixas de seleção |
| **Text High Contrast**| `--color-text-primary`| `#FFFFFF` | `rgb(255, 255, 255)` | Títulos, transcrições em destaque |
| **Text Muted** | `--color-text-secondary`| `#94A3B8` | `rgb(148, 163, 184)` | Timestamps, contadores de lote, metadados |
| **Success Status** | `--color-status-success`| `#10B981` | `rgb(16, 185, 129)` | Transcrição concluída com sucesso |
| **Warning / Fallback** | `--color-status-warning`| `#F59E0B` | `rgb(245, 158, 11)` | Tradução automática aplicada |
| **Error Status** | `--color-status-error` | `#EF4444` | `rgb(239, 68, 68)` | Vídeo sem legenda disponível |

---

## 3. Tipografia Recomendada
- **Títulos e Logotipo:** Inter, SF Pro Display ou Roboto (Font Weight: 700 / 800 Bold)
- **Interface e Corpo:** Inter ou Roboto (Font Weight: 400 Regular, 500 Medium)
- **Timestamps e Códigos (SRT/JSON):** JetBrains Mono, Fira Code ou Roboto Mono

---

## 4. O Símbolo (O Play de Linhas)
O símbolo une o ícone universal de mídia (*Play Triangle*) com a estrutura rítmica de transcrição e legendas (linhas horizontais de larguras e segmentações variadas).
- As linhas superiores carregam o tom coral da marca (`#FF4444`), degradando progressivamente para o branco puro (`#FFFFFF`).
- A segmentação de certas barras emula parágrafos e pausas de fala, comunicando imediatamente a conversão de áudio em texto.
