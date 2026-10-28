# Readiness local da V1 — independente de GitHub Actions

**Escopo (2026-10-28).** A aplicação vive em `../pncp-opportunity-agent`; este repositório contém o Docker Compose. O GitHub Actions da aplicação está **indisponível por créditos**, conforme comunicado pelo responsável; [issue #40](https://github.com/fernandosam/pncp-opportunity-agent/issues/40). Esta limitação **não autoriza bypass** do gate de release por SHA nem a marcação do DoD como concluído. Reúna evidências locais agora e deixe a execução do GitHub Actions para o fim.

Não ativar worker, chamar Groq/Resend, iniciar uma nova verba, aplicar migrations, publicar domínio ou destruir volumes como consequência destes checks. O ensaio real de entrega exige autorização separada; custos/reservas anteriores não são zerados por um novo banco Docker.

## 1. Verificações executáveis sem GitHub Actions

Na raiz deste repositório, com os dois checkouts irmãos:

```bash
# Executa testes sintéticos dos verificadores (sem Docker ou providers reais).
bash tests/readiness-scripts.test.sh
bash tests/restore-isolated.test.sh            # fixtures de segurança; sem Docker real

# Usar sempre o SHA completo revisado; Node.js 24, pnpm 10 e
# Playwright/Chromium instalados são pré-requisitos do runner local.
APP_SHA=$(git -C ../pncp-opportunity-agent rev-parse HEAD)
bash scripts/check-app-local.sh "$APP_SHA"

# Em host com Docker Compose já provisionado e web/database em execução.
# Somente consulta banco, testa TLS/RLS e consulta health/readiness HTTP locais.
# Falha se encontrar worker ativo: é um check PRE-ATIVAÇÃO.
bash scripts/check-stack-readonly.sh

# Apenas lê arquivos cifrados em ./backups; exige backup recente (<=36h),
# permissões restritas e ausência de cópias com 7+ dias.
bash scripts/check-backup-health.sh
```

`check-app-local.sh` executa exatamente as etapas funcionais da pipeline CI: `pnpm install --frozen-lockfile`, lint, typecheck, unit, integração, build, `pnpm audit --audit-level high` e Playwright E2E. Executa os comandos com `env -i` e **placeholders idênticos ao CI para chaves Groq/Resend, URL do PostgreSQL, modelo e orçamento**, removendo outras variáveis herdadas, inclusive eventuais credenciais reais. A flag `CI=1` também impede o Playwright de reutilizar um servidor na porta 3100 que não pertence ao teste. O script executa `pnpm exec playwright install chromium` antes do E2E (é possível precisar de dependências de sistema adicionais). A instalação e o audit podem acessar os registros públicos de pacotes/vulnerabilidades, mas **não devem chamar Groq/Resend**; nenhum worker é ativado. A verificação do isolamento está em `tests/check-app-local.test.sh`.  Confere versão Node/pnpm, checkout limpo e SHA antes de executar. Se qualquer etapa falhar, interrompe a sequência. A captura deve incluir o SHA e códigos de saída, sem tokens e sem dados sensíveis.

`check-stack-readonly.sh` lê o Compose de modo seguro (`config --quiet`), verifica database/web healthy, worker parado, migration `015_auth_capability_rls`, RLS forçada, conexão TLS com identidade validada e respostas locais `/api/health` e `/api/ready` HTTP 200 com `no-store`. **Não** inicia serviço novo, não substitui um teste de navegador e não comprova entrega por e-mail. No host, a execução deve ocorrer usando as configurações e volumes verdadeiros — os testes unitários com Docker simulado apenas verificam o comportamento dos scripts.

`check-backup-health.sh` não cria nem descriptografa backup; constata somente presença, idade, modo e expiração de arquivos `.age`. Um resultado PASS **não substitui restauração**. A agenda `backup-scheduler` é opt-in e precisa de evidência de execução/monitoramento. Backups apenas locais não protegem contra perda total do host; registrar essa decisão de risco e validar o RPO/RTO antes de produção.

## 2. Exercícios em ambiente isolado — com operador no host

| Exercício | Como registrar evidência | Aceite |
|---|---|---|
| Backup / restauração | Executar `scripts/restore-isolated.sh pncp-restore-<id> <backup.age> <identity>` **somente** com identidade e arquivo local autorizados, em projeto novo sem dados; verificar migrations, RLS, contagens, tempo de recuperação. Nunca restaurar no banco ativo. | Verificação de pós-restore de migration 015, RLS forçada e `pncp_app` sem superuser/bypass; Resultado observado; RPO/RTO assinados por responsável. |
| Retenção | Conferir rotina `runRetention` realmente agendada/rodada, tempos de expurgo 30d/90d/12m e exclusão de empresa em ambiente de teste, sem criar dados em produção. | Prova de expurgo e privacidade. |
| Falha e recuperação | Em fixture de worker isolado e com provedores simulados, reproduzir lease expirado, repetição de job, timeout PNCP, schema LLM inválido e outbox em falha. | Sem job/entrega duplicados; uso/reservas incertas preservados. |
| Acessibilidade | Inspeção real das telas de login/perfil/dashboard/detalhe/feedback em 320, 375, 768 e 1440 px, zoom 200%, teclado e leitor de tela. | Registro de defeitos, correções e aceite humano. |
| Segurança / operação | Revisar configuração HTTPS efetiva, permissões de segredos, proxy sem log de links com token, click tracking desativado, logs redigidos, monitoramento, alertas e plano de rollback. | Evidências da configuração real e aceite de riscos. |
| Canário positivo | Com autorização explícita de fontes, orçamento, destinatário e tempo, rodar empresa → PNCP → documentos → Groq → briefing elegível → Resend/outbox → detalhe → feedback → Precision@K. | Logs allowlisted e resultado real; não fabricar MATCH, briefing, entrega ou feedback. |

Estes exercícios **não foram executados pelo autor deste pacote no host Docker**. A documentação existente comprova ensaios históricos locais de login, TLS/RLS e restore; isso não prova o release final.

## 3. Evidência e condição de liberação

Copie apenas metadados não sensíveis para a [issue #25](https://github.com/fernandosam/pncp-opportunity-agent/issues/25): data/hora com fuso, SHA de cada repositório, versões de Node/pnpm/Docker, comando, exit code, resultados agregados, IDs de imagens, evidências de rollback/restore e decisão de risco. **Não** publique `.env`, URLs com magic-link, cookies, destinatários, dados de tenants ou arquivos de backup.

Estado inicial deste pacote:
- **Concluído pelo autor:** análise estática do contrato Compose, scripts e migrations; `bash -n` dos verificadores; testes isolados dos verificadores com Git/Docker/pnpm simulados.
- **A executar no host:** `check-app-local.sh`, `check-stack-readonly.sh`, `check-backup-health.sh`, restore isolado e ensaios com navegador.
- **Somente com autorização:** chamadas reais PNCP/Groq/Resend, worker contínuo e cutover.
- **Último gate (depois de créditos):** CI e Docker GitHub Actions **verdes no SHA exato**, checklist §1–9 realmente sustentado por evidências, `pnpm release:gate preflight`, aprovação humana na #25 após CI e `pnpm release:gate verify`. Sem isso, **não liberar produção**.

O preflight de produção `bash scripts/release-preflight.sh <SHA>` é separado: exige `APP_IMAGE_TAG` idêntica ao SHA e `APP_URL` HTTPS público, portanto não se aplica ao bootstrap `https://localhost`.

## Contratos do restore isolado (teste sem Docker real)

`bash tests/restore-isolated.test.sh` executa o script contra um simulador do comando `docker`: deve rejeitar nome de projeto não isolado, arquivo/identidade ausentes, destino com objetos, falha de descriptografia, erro em pg_restore e falha do pós-check RLS. Um restore aparente não é aceito sem o postflight de migration 015, RLS de tenant forçada e runtime sem superuser/NOBYPASSRLS. O ensaio simulado **não verifica o PostgreSQL real, a identidade age, conteúdo do arquivo ou tempo de recuperação**; para satisfazer o DoD, restaurar backup real em projeto novo autorizado e registrar RTO/RPO observados.
