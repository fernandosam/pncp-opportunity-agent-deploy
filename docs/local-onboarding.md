# Provisionamento local — cadastro pronto, autenticação bloqueada por RLS

Pedido do usuário: executar cadastro/perfil/configuração e ensaio controlado, reutilizando perfil anterior. O schema atual não armazena nome legal/CNPJ: `companies` exige id/fuso; `responsible_users` exige id/company_id/email. Não foram inventados dados legais.

## Feito

- Novo tenant interno UUID (não alias do tenant histórico), fuso America/Sao_Paulo; responsável é o destinatário já autorizado. Identificadores/dados pessoais permanecem em arquivos privados fora do Git.
- Perfil comercial anterior recuperado de duas capturas privadas consistentes, somente campos comerciais; novo id/version=1 validado por `createCommercialProfile`. Cadastro de empresa/responsável/perfil em uma transação administrativa, advisory lock e guardas contra conflito/duplicação; confirmação read-only: uma linha em cada tabela.
- Não houve importação de oportunidades, avaliações, claims, jobs, ledger, sessões ou feedback antigo. Compromisso histórico US$ 0,152960 preservado nas evidências.
- Groq e Resend staging configurados apenas nos env files privados chmod600. Resend sandbox onboarding@resend.dev, chave com sending_access; não ampliar para full_access. Leitura de mensagens via API é corretamente recusada com restricted_api_key.
- HTTPS local Caddy em https://localhost, portas 80/443 publicadas somente em 127.0.0.1 por padrão; APP_URL alinhado. CA local exportada para `.secrets/web-ca.crt`, chain/hostname verificados com curl --cacert, sem -k. Nenhuma CA instalada globalmente no sistema/navegador.
- Banco/web healthy, HTTPS readiness ready, smoke TLS/RLS/worker NODE_ENV=test passou.

## Bloqueio comprovado, não delivery/session comprovados

O formulário retornou resposta genérica de não enumeração. Auditoria posterior: **magic_link_tokens=0, sessions=0, ledger LLM=0**. Essa resposta NÃO comprova envio, entrega ou login.

Prova nativa PostgreSQL read-only com o próprio `PgAuthRepository`:
1. Admin verifica responsável provisionado.
2. SET LOCAL ROLE pncp_app; findPrincipalByEmail retorna null sem tenant.
3. SET LOCAL app.company_id para o tenant provisionado; mesma consulta encontra o responsável.

Causa: `PgAuthRepository` usa consultas globais pré-autenticação, mas as políticas existentes permitem somente tenant já conhecido. Também é necessário proteger criação/consumo de magic link e resolução/revogação de sessão no fluxo pré-auth. Não resolver com superuser/BYPASSRLS no runtime nem política USING(true).

A correção exige acesso pré-auth restrito por e-mail/hash/capability e transações/contexto seguros, com testes sob role non-superuser. **Migration/alteração de schema não aplicada: aguarda aprovação humana explícita para o Docker local.**

## Segurança operacional até a correção

Worker automático desligado; allowlist foi novamente esvaziada para impedir ativação acidental. Credenciais preparadas não autorizam daemon. Limites preparados: uma avaliação, US$ 0,034/interpretação e US$ 0,034/dia. Isso é apenas teto técnico, não renovação do ensaio/global budget. ZERO chamadas LLM; nenhuma sessão/token fabricada ou auth forjada.

Após aprovação/correção: testar request→e-mail real→redeem único→sessão→perfil autenticado; navegador precisa confiar na CA local (decisão de trust separada). Só então executar ensaio único controlado com fontes novas e sem repetir registros do histórico, preservando teto global antigo. Produção/§10 continuam sem aprovação.
