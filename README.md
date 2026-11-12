# TubExtractor

Nome no aparelho: TubExtractor. Repositório e pacote Android: Subshaul (`com.fabriciocotrim.subshaul`), mantidos para a atualização instalar por cima.
Marca, ícones e fichas de loja: `artefatos/` (ver `artefatos/docs/BRAND_GUIDELINES.md`).

App Android que baixa transcrições do YouTube em lote. Sem conta, sem servidor e sem custo.

## O que faz

- Aceita vídeo, playlist, canal, @handle, Shorts ou vários links (um por linha).
- Recebe links pelo botão **Compartilhar** do app do YouTube.
- Lê até 500 vídeos por vez, do mais novo para o mais antigo.
- Exporta em TXT, SRT, VTT, Markdown ou JSON, com ou sem timestamps.
- Tem mais de 100 idiomas. Se o idioma não existe, tenta a tradução do YouTube. Se a tradução falha, usa a faixa original.
- Mostra o status de cada vídeo e o motivo de cada falha.
- Busca dentro da transcrição e copia tudo.
- Gera um ZIP com `transcripts/`, `manifest.csv` e `manifest.json`.
- Guarda o histórico e um cache no aparelho. Um job interrompido continua quando o app abre de novo.

## Instalar

Baixe o `.apk` na página [Releases](../../releases) e abra no celular. O Android pede para permitir a instalação de fontes desconhecidas.

## Como funciona

```
Link ──► parser (só hosts do YouTube) ──► lista de vídeos
     ──► fila (2 em paralelo, pausa, nova tentativa em 429)
     ──► API interna do YouTube (cliente ANDROID → IOS)
     ──► cache local ──► leitor / exportação / ZIP
```

Todo o conhecimento sobre a API do YouTube fica em `lib/core/youtube_client.dart`. Quando o YouTube mudar algo, rode:

```
dart run tool/live_check.dart
```

## Desenvolvimento

```
flutter test                 # testes de unidade
flutter build apk --release  # APK assinado (precisa de android/key.properties)
```

A chave de assinatura fica fora do repositório. Sem ela, uma versão nova não instala por cima da antiga.

Não é afiliado ao YouTube nem ao Google.
