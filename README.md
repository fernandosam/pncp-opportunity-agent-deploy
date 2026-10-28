# PNCP Opportunity Agent — Docker deployment

Repositório de operação independente do código em `../pncp-opportunity-agent`. Stack: Next.js web, worker Node, PostgreSQL **18**, migrations one-shot, backup **age** e HTTPS opcional Caddy. Não depende de Vercel/Railway para executar. Não há produção automaticamente autorizada.

## Pré-requisitos

Docker Engine/Desktop com Compose v2, Bash e OpenSSL. No WSL, habilite a integração da sua distribuição no Docker Desktop. Mantenha os dois repositórios lado a lado em `factory-ia`; `APP_SOURCE` permite apontar para um checkout revisado diferente.

## Primeiro boot — banco novo e isolado

```bash
cp .env.example .env
./scripts/init.sh                 # não sobrescreve segredos existentes
# Validar sem exibir URLs/senhas/PEM renderizados:
docker compose config --quiet
docker compose --profile maintenance --profile worker build
docker compose up -d --wait database
# Somente banco NOVO ou migrations explicitamente revisadas/autorizadas:
docker compose --profile maintenance run --rm migrate
docker compose up -d --wait web
./scripts/smoke.sh
```

Web: http://localhost:3000. Banco sem porta publicada, rede interna isolada, TLS com CA/hostname verificados e rejeição de conexões TCP sem TLS. Runtime `pncp_app` não é superuser nem bypassa RLS; apenas migration/backup recebem credenciais administrativas. Web/worker executam como UID 1000, filesystem readonly, capabilities removidas. Logs Docker têm rotação, sem payloads/segredos. Certificado de banco dura 365 dias: monitorar/renovar antes de expirar; não desabilitar verificação.

`init.sh` cria `.env.app`, `.env.worker`, `.env.database`, `.env.migrate`, `.env.backup` e `.secrets` (600/700), com senhas e segredo de feedback novos. **Não comitar nem imprimir** esses arquivos. Em restore, mantenha/reaplique o segredo de feedback original se houver capacidades já entregues, inclusive previous secrets durante rotação. Não trocar senha no arquivo com um volume já inicializado: PostgreSQL não reaplica POSTGRES_PASSWORD; use ALTER ROLE controlado ou preserve configuração original.

Configure `RESEND_API_KEY`/remetente em `.env.app` e `.env.worker` para autenticação/briefings reais. O bootstrap deixa as chaves vazias, não finge entrega e não chama provedores.

## Worker opt-in

**Estado do onboarding (2026-10-14):** migration de autenticação `015_auth_capability_rls` aplicada **somente no Docker local**; recebimento do magic link, login HTTPS e acesso ao perfil confirmados pelo responsável. O dashboard tenant-scoped foi implantado localmente, mas não havia briefings reais persistidos. Worker continua desligado, allowlist vazia e fluxo positivo/entrega/feedback/Precision@K não comprovados. Não extrapolar a aprovação local da #31 para produção. [Evidências](docs/local-onboarding.md).

Worker não inicia no boot padrão. A reconciliação sem importação foi concluída: [relatório](docs/data-reconciliation.md). Este é um banco novo/vazio; importação não é requisito. Antes de ligar, cadastrar empresa/responsável/perfil reais e conferir tenant IDs, credenciais, fontes e orçamento autorizado:

```bash
docker compose --profile worker up -d worker
```

Edite `WORKER_COMPANY_IDS`, `OPENAI_API_KEY` e limites em `.env.worker`; mantenha o mesmo segredo de feedback da web. Defaults conservadores: v3, US$ 0,034/interpretação, US$ 0,20/dia, 4 avaliações/run. **US$ 0,20/dia não é autorização para consumo autônomo ou para resetar o teto total do ensaio anterior.** O ensaio antigo continua suspenso; custos desconhecidos do histórico permanecem registrados nas evidências, não são cancelados pelo banco novo. Não retomar/reexecutar o ensaio antigo usando um ledger vazio. Smoke do worker usa NODE_ENV=test, sem LLM/e-mail.

## HTTPS público

Para host explicitamente aprovado: DNS para o servidor; portas 80/443; `PUBLIC_HOST=host.example` e `APP_URL=https://host.example` em `.env`. Compose aplica o mesmo APP_URL a web/worker, substituindo o valor de bootstrap.

```bash
docker compose --profile edge up -d edge
```

Caddy gerencia TLS e encaminha para web; access log desligado para não registrar magic-link/feedback query strings. Web permanece em loopback; não publicar PostgreSQL. CDNs/APM/proxies externos ainda exigem revisão de redação. Nenhum domínio/produção/cobrança é ativado pelo bootstrap.

## Backups cifrados — retenção 7 dias

Obtenha/crie uma identidade age **fora do Git**, guarde no cofre e em cópia fora deste host. Grave somente seu destinatário público `age1...` em `.secrets/backup.recipient` (600). A chave privada não é montada no serviço de backup.

```bash
./scripts/backup.sh
# Agenda diária 03:30 UTC, explicitamente opt-in:
docker compose --profile backups up -d backup-scheduler
```

`pg_dump` PG18 → age por pipe, sem dump plaintext, arquivo temporário promovido atomicamente; expurgo somente após sucesso (`-mtime +6`). Backups em `./backups` (600/700). Alertar ausência/stale/falha, copiar cifrados para o PC/cofre conforme política aceita. Volume Docker não é backup; perder o host sem cópia perde dados. Validar restore/RTO/RPO; não assumir PITR.

## Reconciliação sem importação (decisão atual)

O usuário dispensou a importação. O banco Docker é intencionalmente novo; a auditoria read-only confirmou 14 migrations, 21 tabelas (20 de negócio vazias), 19 RLS e zero constraints não validadas. Histórico Railway foi reconciliado pelas evidências finais disponíveis, preservando US$ 0,152960 de compromisso conservador e três reservas desconhecidas. Ver [relatório completo](docs/data-reconciliation.md).

```bash
./scripts/reconcile.sh  # somente contagens/metadados, sem mutação nem payloads
```

Esse snapshot antecede o cadastro autorizado. O Docker local já contém tenant/responsável/perfil e a autenticação RLS foi corrigida pela migration 015, com login real confirmado (ver onboarding). Worker continua desligado e allowlist vazia. Novas operações exigem orçamento e ativação explicitamente autorizados — não assumir novo saldo pelo ledger vazio.

## Restore/rehearsal e importação opcional futura

Não ativar cobrança Railway, excluir seu volume nem restaurar sobre banco ativo. O trial expirado deixou o volume original preservado. Obter snapshot íntegro/autorizado ou selecionar backup cifrado com **RPO explicitamente aceito**; um backup anterior pode não conter as quatro avaliações recentes nem o ledger mais novo. **Bootstrap vazio não significa que os dados Railway foram migrados.**

```bash
./scripts/restore-isolated.sh pncp-restore-review /path/snapshot.dump.age /path/identity.txt
```

O script exige projeto `pncp-restore-*`, recusa destino que contenha objetos de usuário, usa stream age→pg_restore em transação e preserva volumes/origem. Restore só em banco novo, com PG18. Validar contagens, migrations, políticas RLS, tenant/session, reservas desconhecidas, claims/outbox/feedback e backup. Aplicar o grant de runtime após importação. Após aceite humano, escolha esse projeto restaurado para o cutover e configure porta/envs; não sobrescreva o banco novo já usado por outro ambiente.

## Preflight entre aplicação e Docker (somente leitura)

Antes de qualquer release, selecione e revise o **SHA completo da aplicação** no repositório irmão. No arquivo privado `.env` do deploy, configure `APP_IMAGE_TAG` com esse mesmo SHA, `APP_SOURCE` com o checkout correto e `APP_URL` com o domínio público HTTPS aprovado. O Compose usa `environment.APP_URL` e **sobrescreve o valor de `.env.app`**; conferir somente `.env.app` não é suficiente.

```bash
# Inspeção local: nenhum build, migration, chamada externa ou ativação do worker.
bash scripts/release-preflight.sh <SHA_COMPLETO_DA_APLICACAO>
```

O preflight exige worktrees Git limpas, checkout da aplicação no SHA informado, `APP_IMAGE_TAG` idêntica ao SHA, `APP_URL` HTTPS não-localhost e `docker compose config --quiet`, sem imprimir segredos. Ele **não verifica nem substitui** CI verde no SHA, imagens compiladas, prova E2E real, restauração/retention, autorização de orçamento ou assinatura humana da [issue #25](https://github.com/fernandosam/pncp-opportunity-agent/issues/25). O smoke `./scripts/smoke.sh` valida a migration de autenticação 015 e RLS forçada, independentemente de migrations aditivas futuras. A execução requer o Docker do ambiente e serviços efetivamente iniciados.

A validação do release é comandada pelo código da aplicação: `pnpm release:gate preflight`, decisão humana na #25 e `pnpm release:gate verify`. Não executar `up`, `migrate`, `backup-scheduler` ou ativar o worker como consequência de um preflight positivo.

## Releases, rollback e operação

Antes de migrations ou cutover: backup cifrado verificado, SHA/imagens aprovados, worker parado/drain. Pin version/digest das imagens base e registre IDs das imagens construídas. Use `APP_IMAGE_TAG` em `.env` para cada release aprovado (ex.: SHA completo); web/worker/migrate/database/backup têm tags explícitas independentes do nome do projeto Compose. Rollback: selecione tag anterior e execute `up -d --no-build`, sem rebuild nem downgrade de schema. `docker compose build` usa o checkout APP_SOURCE: não mudar esse checkout durante build. Migrations são manuais; rollback do app não faz downgrade do banco e só é seguro com schema compatível. Preserve imagem anterior e volumes; não usar `down --volumes`, prune de volumes ou mudança de major PG.

```bash
docker compose ps
docker compose logs --tail 50 web   # somente logs allowlisted; revisar antes de compartilhar
docker compose stop worker         # drain longo, não forçar kill de LLM em voo
docker compose down               # preserva volumes
```

Gate de produção/revisão humana por SHA permanece no repositório da aplicação. CI/smoke verde não autoriza produção, feedback fabricado ou mudança de schema. Este repositório é Git local; publicação remota/domínio/cutover são etapas separadas.
