# Segurança — TubExtractor

Nome visível e repositório: **TubExtractor**. O applicationId segue `subshaul` (`com.fabriciocotrim.subshaul`), para instalar por cima das versões antigas.

**Classe: R0** — app local, sem backend, sem conta, sem pagamento, sem dado pessoal coletado. [DECISÃO PO, 2026-11-11]

## Bens e ameaças
| Bem | Ameaça | Controle | Teste |
|---|---|---|---|
| Aparelho do usuário | Texto colado/compartilhado malicioso | Parser aceita só hosts do YouTube e IDs `[A-Za-z0-9_-]{11}`; texto compartilhado limitado a 20 mil caracteres | `test/url_parser_test.dart` (grupo "Proteção"); o limite de 20 mil fica em `MainActivity.kt` e não tem teste automático |
| Aparelho do usuário | Título de vídeo com `../` vira caminho no ZIP | Nome de arquivo limpo, sem separador | `test/formatters_zip_test.dart` |
| Planilha do usuário | Título com fórmula (`=HYPERLINK`) no `manifest.csv` | Célula prefixada com `'` | `test/formatters_zip_test.dart` |
| Aparelho do usuário | Resposta do YouTube aponta legenda para outro host | Só busca `https://*.youtube.com` | `test/youtube_client_test.dart` |
| Atualização do app | APK assinado por engano com a chave de debug | Build de release falha sem `android/key.properties` | `android/app/build.gradle.kts` |
| Serviço no ar | Bloqueio do YouTube por excesso | 2 pedidos em paralelo, pausa entre pedidos, nova tentativa com espera; o job pausa após 3 bloqueios sem nenhuma resposta real do YouTube no meio (vídeo sem legenda não zera a conta) | `test/youtube_client_test.dart`, `test/job_runner_test.dart` |
| Memória/disco | Lote gigante | Teto de 500 vídeos por job | `test/youtube_client_test.dart`, `test/job_runner_test.dart` |
| Histórico do usuário | Apagar job por engano (gesto de deslizar) | Um aviso de 5 s com "Desfazer" por busca, em sequência; o tempo só corre com o aviso na tela; os dados só são apagados quando o aviso daquela busca fecha sem desfazer; busca apagada e app fechado na janela → apagada na abertura; falha ao apagar → continua oculta e o app tenta de novo; gesto não concluído nunca apaga busca visível | `test/app_state_test.dart`, `test/home_undo_test.dart`, `test/undo_real_path_test.dart` |
| Atualização do app | Perda da chave de assinatura | Chave fora do repositório (`~/.subshaul-keys`), `android/key.properties` no `.gitignore` | — |

## Fica sem proteção (risco aceito pelo PO)
- Termos do YouTube proíbem acesso automatizado.
- O código do app pode ser copiado (APK). Não há segredo nem regra de valor nele.

## Pacotes (princípio 4)
Todos do pub.dev, com publicador verificado ou mantenedor conhecido e milhões de downloads: `http`, `path_provider`, `shared_preferences`, `share_plus`, `url_launcher` (dart.dev / flutter.dev / fluttercommunity.dev), `archive` (mantido desde 2013), `file_picker` (mantido desde 2018).
Só para testes (não vai no APK): `shared_preferences_platform_interface` (flutter.dev).
Fontes Inter e JetBrains Mono vão dentro do app (`assets/fonts/`, licença OFL). O app não baixa fonte da internet.

## Dados
Nada sai do aparelho além dos pedidos ao YouTube. Sem analytics, sem log em release. Jobs e cache ficam na pasta privada do app. As preferências (tema, idioma, formato, marcação de tempo, limite) ficam no `shared_preferences` do app.

## Portão (fase 7) — 2026-11-12, versão 1.4.1
| Ferramenta | Resultado |
|---|---|
| `gitleaks dir` em `lib`, `android/app/src`, `test`, `assets` e no APK 1.4.1 | sem vazamentos |
| `gitleaks dir .` | 2 achados, ambos em `android/key.properties` (senha da chave; arquivo ignorado pelo git, esperado) |
| `semgrep p/owasp-top-ten p/secrets` | 0 achados, 137 regras, 426 arquivos |
| `osv-scanner` (`pubspec.lock`) | sem vulnerabilidades |
| `flutter test` | 159 testes passando, 5 rodadas seguidas |
| `flutter analyze` | sem avisos |
| `gitleaks git` (histórico) | sem vazamentos (commit inicial `302664f`, antes e depois do push) |
