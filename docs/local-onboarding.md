# Provisionamento local — cadastro pronto, pré-auth corrigido; aceite de login pendente

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

Backup age criado antes da aplicação; ensaio PostgreSQL 18 em projeto Compose isolado comprovou um vencedor em resgate concorrente, replay/expiração/revogação/isolamento e down/up sem apagar dados, com role runtime real non-superuser/NOBYPASSRLS e zero provedores. Fixtures isoladas não são delivery/login reais. Banco local após aplicação: 15 migrations/19 tabelas com RLS forçada, responsável encontrado por lookup restrito, leituras sem contexto vazias; tokens/sessões reais continuam zero. Database/edge preservados, somente web recriado; worker desligado. Imagem de rollback retida `pncp-opportunity-agent-web:rollback-auth-015`.

Detalhes/invariantes/rollback: `../pncp-opportunity-agent/docs/runbooks/autenticacao-local.md`. Ainda falta o usuário solicitar/receber/abrir o link e confirmar sessão/perfil em HTTPS; nenhuma sessão real foi fabricada nem provedor chamado pelos testes. Mudança não aplicada em Railway/produção; commit local não equivale a push/CI/§10.

## Correção da configuração efetiva de envio após teste humano

O usuário solicitou um link, mas não recebeu. Telemetria registrou `AUTH_EMAIL_DELIVERY_FAILED` antes da chamada ao provedor: o web em produção usava APP_URL HTTP. O `environment.APP_URL` do Compose sobrescrevia o HTTPS de `.env.app` com o valor antigo de `.env`.

Corrigido **somente o arquivo privado `.env`** para `APP_URL='https://localhost'` (chmod600), recriando apenas web; database/edge IDs/imagens preservados, worker desligado, health/ready e origem HTTPS efetiva confirmados. Prova de configuração com o sender real em container sem rede, fetch mock e destinatário/token explicitamente de fixture passou; zero provedores e zero escrita em banco. Isso não comprova validade da chave/entrega: o usuário deve solicitar um link novo e confirmar recebimento/acesso.

Para este Compose, **`.env` é a origem efetiva de APP_URL**; mudar somente `.env.app` não basta. Sempre conferir a configuração efetiva do web após recriação, sem imprimir env/secrets. Não contornar a exigência HTTPS nem ampliar a chave Resend.

## Segurança operacional e aceite humano pendente

Worker automático desligado; allowlist foi novamente esvaziada para impedir ativação acidental. Credenciais preparadas não autorizam daemon. Limites preparados: uma avaliação, US$ 0,034/interpretação e US$ 0,034/dia. Isso é apenas teto técnico, não renovação do ensaio/global budget. ZERO chamadas LLM; nenhuma sessão/token fabricada ou auth forjada.

Após a correção local, validar humanamente request→e-mail real→redeem único→sessão→perfil autenticado; navegador precisa confiar na CA local (decisão de trust separada). Só então executar ensaio único controlado com fontes novas e sem repetir registros do histórico, preservando teto global antigo. Produção/§10 continuam sem aprovação.
