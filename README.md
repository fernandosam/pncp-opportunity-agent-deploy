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

## Backups cifrados — operação simplificada

O utilitário [`backupctl`](backupctl) é a interface única para verificar a saúde, criar, listar e **testar a restauração** de backups age. Usa os scripts existentes por trás da interface; não altera schema, não ativa worker, não chama Groq/Resend, não exige GitHub Actions.

```bash
./backupctl status                    # TLS, agendador e cópia recente (somente leitura)
./backupctl list                      # nomes, tamanhos e timestamps dos backups cifrados
./backupctl run                       # backup agora; depois aplica a retenção de sete dias
./backupctl verify --identity /caminho/privado/age-identity.txt
# Opcional: descarta somente o novo volume isolado após SUCESSO da verificação:
./backupctl verify --identity /caminho/privado/age-identity.txt --cleanup

# Teste do próprio utilitário sem Docker ou segredos reais:
bash tests/backupctl.test.sh
```

`verify` escolhe o arquivo mais recente ou aceita `--backup /caminho/arquivo.dump.age`, cria um projeto `pncp-restore-check-*` novo, usa `restore-isolated.sh` para descriptografar/ restaurar e verificar migration 015, RLS forçada e role de menor privilégio; imprime a duração observada. **Não restaura o banco ativo**. Por segurança o volume de teste é **preservado por padrão**; `--cleanup` precisa ser solicitado explicitamente e só atua após sucesso. Com falha, o ambiente isolado é preservado para diagnóstico. É necessário acesso à identidade age privada em arquivo local com modo 600/400; ela não é copiada para o Git.

**Identidade age:** a opção `--identity` exige a **chave privada original** correspondente a `.secrets/backup.recipient` (o destinatário `age1...` é público e não serve como identidade). Não passe um backup `.dump.age` como identidade e não gere uma nova chave esperando abrir arquivos antigos. O restaurador agora autentica toda a descriptografia e o cabeçalho `PGDMP` **antes de criar o banco isolado**; falhas de identidade encerram com orientação sem criar volume PostgreSQL. Consulte [diagnóstico de chaves age](docs/backupctl.md#diagnóstico-de-chave-age-e-preflight-de-restauração).

O agendador diário existente roda às **03:30 UTC**, com opt-in já ativado pelo operador. Se ainda estiver desligado em outro host, sua ativação permanece decisão separada: `docker compose --profile backups up -d backup-scheduler`. O armazenamento cifrado fica em `./backups`, retenção máxima sete dias; o arquivo mais recente não prova restore. A integridade do restore precisa ser validada com **backup real no host**, não só com fixtures. O teste não comprova PITR, cópia off-host, RPO/RTO aceitáveis ou alertas externos. Antes de depender exclusivamente deste host, defina política de cópia externa e aceite o risco de perda do disco.

Detalhes, opções, privilégios e limitações: [guia do backupctl](docs/backupctl.md).

## Reconciliação sem importação (decisão atual)

O usuário dispensou a importação. O banco Docker é intencionalmente novo; a auditoria read-only confirmou 14 migrations, 21 tabelas (20 de negócio vazias), 19 RLS e zero constraints não validadas. Histórico Railway foi reconciliado pelas evidências finais disponíveis, preservando US$ 0,152960 de compromisso conservador e três reservas desconhecidas. Ver [relatório completo](docs/data-reconciliation.md).

```bash
./scripts/reconcile.sh  # somente contagens/metadados, sem mutação nem payloads
```

Esse snapshot antecede o cadastro autorizado. O Docker local já contém tenant/responsável/perfil e a autenticação RLS foi corrigida pela migration 015, com login real confirmado (ver onboarding). Worker continua desligado e allowlist vazia. Novas operações exigem orçamento e ativação explicitamente autorizados — não assumir novo saldo pelo ledger vazio.

## Restore/rehearsal e importação opcional futura

O procedimento simplificado de ensaio é `./backupctl verify --identity /caminho/privado/age-identity.txt` (inclua `--backup ARQUIVO` para selecionar um backup específico). Internamente ele reutiliza `scripts/restore-isolated.sh`, que restaura em banco PostgreSQL 18 independente, recusa dados preexistentes e verifica migration 015, RLS forçada e `pncp_app` sem SUPERUSER/BYPASSRLS.

**Não** restaurar sobre o banco ativo, não apagar volumes sem aceite, não ligar worker e não assumir que o backup Docker contém dados do Railway antigo. Restore real, RTO/RPO e eventuais importações futuras continuam sujeitos à autorização de cada ambiente; o ledger atual não substitui o histórico de reservas anterior.

## Verificação local da V1 (sem GitHub Actions)

Enquanto o CI da aplicação estiver indisponível por créditos, registre evidências **locais** sem enfraquecer o gate de produção. Com os dois repositórios lado a lado e o SHA da aplicação revisado:

```bash
bash tests/readiness-scripts.test.sh             # fixtures; sem Docker/provedores
bash tests/restore-isolated.test.sh            # recusa destino ocupado e falhas na restauração
APP_SHA=$(git -C ../pncp-opportunity-agent rev-parse HEAD)
bash scripts/check-app-local.sh "$APP_SHA"        # lint, types, unit, integração, build, audit, E2E
bash scripts/check-stack-readonly.sh             # Docker real, web/banco healthy, worker parado
bash scripts/check-backup-health.sh              # frescor/permissões/retenção dos backups locais
```

O verificador da aplicação executa os comandos sob `CI=1` e um ambiente isolado com placeholders para Groq, Resend e PostgreSQL; assim não herda as credenciais reais do shell e o Playwright não reutiliza um servidor anterior. Ele instala o Chromium para E2E (pode necessitar dependências do sistema e download de pacotes). **Isso não executa o fluxo positivo com provedores reais**.\n\nOs dois últimos comandos exigem Docker existente e/ou backups locais. Não inicializam serviços, não ativam worker e não chamam Groq/Resend. O check de backup não prova restauração. **Não foram executados no host do responsável nesta entrega.** Procedimentos, matriz de evidências, exercícios manuais e critérios de não-liberação: [readiness local da V1](docs/local-readiness-v1.md). A [issue #40](https://github.com/fernandosam/pncp-opportunity-agent/issues/40) mantém o bloqueio GitHub Actions para o **gate final**, após as demais validações.

## Saúde operacional de backups e TLS (somente leitura)

Este controle **não ativa** o agendador. Depois que o responsável configurar e iniciar explicitamente `backup-scheduler` e que uma primeira cópia real for concluída, executar:

```bash
bash tests/operations-readonly.test.sh  # OpenSSL real e Docker simulado, sem serviços
bash scripts/check-operations-readonly.sh  # host Docker real, sem mutações
```

A inspeção exige (1) CA/certificado PostgreSQL válido para `database` e com **mais de 30 dias** até expirar, (2) diretório de segredos `0700` e chave privada `0600`, (3) contêiner `backup-scheduler` em execução, (4) backup age mais recente com até 36 horas e sem arquivos com idade >=7 dias; não imprime certificados, chaves ou `.env`. Um resultado **FAIL é esperado** no Docker local enquanto o agendador opt-in não estiver habilitado. Não usar aprovação de deploy para habilitá-lo automaticamente.

Não confundir esses controles com validação de conteúdo do backup, restore com chave real, alertas externos, cópia fora do host ou retenção de registros da aplicação; continuam evidências manuais separadas na [issue #25](https://github.com/fernandosam/pncp-opportunity-agent/issues/25). Ver [readiness local](docs/local-readiness-v1.md).

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
