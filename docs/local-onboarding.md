# Provisionamento local — cadastro pronto e login/perfil confirmados pelo usuário

Pedido do usuário: executar cadastro/perfil/configuração e ensaio controlado, reutilizando perfil anterior. O schema atual não armazena nome legal/CNPJ: `companies` exige id/fuso; `responsible_users` exige id/company_id/email. Não foram inventados dados legais.

## Feito

- Novo tenant interno UUID (não alias do tenant histórico), fuso America/Sao_Paulo; responsável é o destinatário já autorizado. Identificadores/dados pessoais permanecem em arquivos privados fora do Git.
- Perfil comercial anterior recuperado de duas capturas privadas consistentes, somente campos comerciais; novo id/version=1 validado por `createCommercialProfile`. Cadastro de empresa/responsável/perfil em uma transação administrativa, advisory lock e guardas contra conflito/duplicação; confirmação read-only: uma linha em cada tabela.
- Não houve importação de oportunidades, avaliações, claims, jobs, ledger, sessões ou feedback antigo. Compromisso histórico US$ 0,152960 preservado nas evidências.
- Groq e Resend staging configurados apenas nos env files privados chmod600. Resend sandbox onboarding@resend.dev, chave com sending_access; não ampliar para full_access. Leitura de mensagens via API é corretamente recusada com restricted_api_key.
- HTTPS local Caddy em https://localhost, portas 80/443 publicadas somente em 127.0.0.1 por padrão; APP_URL alinhado. CA local exportada para `.secrets/web-ca.crt`, chain/hostname verificados com curl --cacert, sem -k. Nenhuma CA instalada globalmente no sistema/navegador.
- Banco/web healthy, HTTPS readiness ready, smoke TLS/RLS/worker NODE_ENV=test passou.

## Bloqueio histórico comprovado (superado pela migration 015 local)

O formulário retornou resposta genérica de não enumeração. Auditoria posterior: **magic_link_tokens=0, sessions=0, ledger LLM=0**. Essa resposta NÃO comprova envio, entrega ou login.

Prova nativa PostgreSQL read-only com o próprio `PgAuthRepository`:
1. Admin verifica responsável provisionado.
2. SET LOCAL ROLE pncp_app; findPrincipalByEmail retorna null sem tenant.
3. SET LOCAL app.company_id para o tenant provisionado; mesma consulta encontra o responsável.

Causa: `PgAuthRepository` usa consultas globais pré-autenticação, mas as políticas existentes permitem somente tenant já conhecido. Também é necessário proteger criação/consumo de magic link e resolução/revogação de sessão no fluxo pré-auth. Não resolver com superuser/BYPASSRLS no runtime nem política USING(true).

A correção exige acesso pré-auth restrito por e-mail/hash/capability e transações/contexto seguros, com testes sob role non-superuser. **Na prova histórica, a migration não estava autorizada/aplicada.** O usuário posteriormente autorizou explicitamente preparar/aplicar a correção somente no Docker local (#31).

## Correção local autorizada e aplicada

Migration `015_auth_capability_rls`: três policies SELECT-only por hash de e-mail/link/sessão, sem superuser/BYPASSRLS/SECURITY DEFINER e sem alteração de grants; FKs compostas validam concordância empresa/responsável. Adapter pré-auth verifica a capability antes de vincular tenant em transação local. Readiness passa a exigir 015. Callback usa redirects relativos para preservar HTTPS/localhost atrás do proxy.

Backup age criado antes da aplicação; ensaio PostgreSQL 18 em projeto Compose isolado comprovou um vencedor em resgate concorrente, replay/expiração/revogação/isolamento e down/up sem apagar dados, com role runtime real non-superuser/NOBYPASSRLS e zero provedores. Fixtures isoladas não são delivery/login reais. Banco local após aplicação: 15 migrations/19 tabelas com RLS forçada, responsável encontrado por lookup restrito, leituras sem contexto vazias; tokens/sessões reais eram zero nessa inspeção anterior ao teste humano. Database/edge preservados, somente web recriado; worker desligado. Imagem de rollback retida `pncp-opportunity-agent-web:rollback-auth-015`.

Detalhes/invariantes/rollback: `../pncp-opportunity-agent/docs/runbooks/autenticacao-local.md`. O aceite humano de recebimento/link/sessão/perfil em HTTPS foi posteriormente confirmado pelo usuário (ver abaixo); nenhuma sessão real foi fabricada nem provedor chamado pelos testes. Mudança não aplicada em Railway/produção; commit local não equivale a push/CI/§10.

## Correção da configuração efetiva de envio após teste humano

O usuário solicitou um link, mas não recebeu. Telemetria registrou `AUTH_EMAIL_DELIVERY_FAILED` antes da chamada ao provedor: o web em produção usava APP_URL HTTP. O `environment.APP_URL` do Compose sobrescrevia o HTTPS de `.env.app` com o valor antigo de `.env`.

Corrigido **somente o arquivo privado `.env`** para `APP_URL='https://localhost'` (chmod600), recriando apenas web; database/edge IDs/imagens preservados, worker desligado, health/ready e origem HTTPS efetiva confirmados. Prova de configuração com o sender real em container sem rede, fetch mock e destinatário/token explicitamente de fixture passou; zero provedores e zero escrita em banco. Essa prova offline não comprovava validade da chave/entrega. O usuário solicitou um novo link e posteriormente confirmou recebimento/acesso.

Para este Compose, **`.env` é a origem efetiva de APP_URL**; mudar somente `.env.app` não basta. Sempre conferir a configuração efetiva do web após recriação, sem imprimir env/secrets. Não contornar a exigência HTTPS nem ampliar a chave Resend.

## Aceite humano registrado

Após a correção da origem HTTPS, o usuário informou “Funcionou” e confirmou explicitamente que abriu o link e acessou o perfil. Recebimento/resgate/acesso reais aceitos **no Docker local**, por confirmação humana; sem captura de tokens/cookies, métricas ou provas de delivery inventadas. #31 concluída nesse escopo, sem liberação de produção/§10. Dashboard com leitura real foi entregue localmente em #39 (ver abaixo); fluxo legítimo de briefing/feedback/Precision@K permanece pendente.

## Dashboard de briefings aplicado no web local

Commit local da aplicação `1650e82` (#39): leitura por empresa autenticada, sete briefings por página, histórico por data e itens ordenados ligados ao detalhe. Estados separados para ausência, falha, data inválida e carregamento; score/ação/motivos/riscos da seleção histórica, objeto/prazo da publicação atual, sem alegar entrega. Runbook/contrato: `../pncp-opportunity-agent/docs/dashboard-v1.md`.

115 unitários/174 integrações (serial)/83 E2E, tipos/lint/build passaram. Fixtures inspecionadas em 320/375/768/1440 e texto ampliado, sem gravar dados fictícios no runtime. Web reconstruído por git archive/recriado, database/edge IDs e imagens preservados, worker desligado; HTTPS/health/ready e APP_URL HTTPS confirmados, rollback `pncp-opportunity-agent-web:rollback-dashboard-1650e82` retido. Com loading, o GET anônimo pode retornar HTTP200 streaming com redirect para /login; teste verificou redirect e ausência de dados tenant, e E2E confirmou chegada ao login.

Inspeção PostgreSQL18 read-only com role runtime non-superuser/NOBYPASSRLS e contexto de sessão já criada/confirmada pelo usuário: consulta real retorna zero briefings, sem alteração de sessões/registros/migrations (15). Não é prova nova de cookie no navegador nem de briefing positivo. Nenhum provedor, migração, importação, processamento, sessão ou feedback artificial executado. Usuário pode atualizar /dashboard para revisar o empty state real; amostra/entrega/feedback reais ainda dependem de ensaio e orçamento explicitamente autorizados. Sem push/CI do commit ou deploy externo.

## Segurança operacional preservada

Worker automático desligado; allowlist foi novamente esvaziada para impedir ativação acidental. Credenciais preparadas não autorizam daemon. Limites preparados: uma avaliação, US$ 0,034/interpretação e US$ 0,034/dia. Isso é apenas teto técnico, não renovação do ensaio/global budget. ZERO chamadas LLM; nenhuma sessão/token fabricada ou auth forjada.

Login/perfil confirmados não autorizam daemon, orçamento novo ou ensaio automático. Um ensaio único controlado ainda exige autorização de consumo/orçamento, fontes novas e preservação do teto global histórico, sem replay de registros antigos. Confiança da CA no navegador é decisão separada. Produção/§10 continuam sem aprovação.
