# Operação única de backups — `backupctl`

A interface foi criada para reduzir quatro operações a um comando sem reinventar a tecnologia: o banco continua em PostgreSQL 18, o dump segue `pg_dump | age` e a restauração mantém o `scripts/restore-isolated.sh`. O agendador e a política de retenção não foram alterados.

## Comandos

| Comando | Operação | Efeito |
|---|---|---|
| `./backupctl status` | Verifica TLS do banco, backup-scheduler em execução, backup recente (<=36h), permissões e retenção de 7 dias | **Somente leitura** |
| `./backupctl list` | Lista apenas nomes, tamanhos e datas UTC dos arquivos `pncp-*.dump.age` | **Somente leitura** |
| `./backupctl run` | Executa imediatamente o script atual de backup cifrado e verifica a saúde dos arquivos | **Cria backup e expurga arquivos com 7+ dias após sucesso** |
| `./backupctl verify` | Restaura o arquivo mais recente em projeto Docker isolado e testa migração/RLS | **Cria outro banco/volume**, sem alterar o ativo |
| `./backupctl verify --cleanup` | Igual ao anterior, removendo **somente os volumes do projeto de teste recém-criado**, após passar | **Remoção explícita e restrita** |

Exemplos:

```bash
./backupctl status
./backupctl list
./backupctl run

# Identidade privada age em arquivo 0600 ou 0400, fora do Git:
./backupctl verify --identity /local/seguro/identity.age
# Com seleção explícita de outro arquivo cifrado:
./backupctl verify --backup backups/pncp-AAAA.dump.age --identity /local/seguro/identity.age

# Após um teste bem-sucedido, apagar somente o volume temporário novo:
./backupctl verify --identity /local/seguro/identity.age --cleanup

# Suíte sintética de regressão, sem Docker/banco/identity reais:
bash tests/backupctl.test.sh
```

Se `--identity` não for fornecido em terminal interativo, será solicitado apenas **o caminho** do arquivo; em execução não interativa o comando falha e exige o argumento. Nunca passar o conteúdo da identidade na linha de comando. O comando verifica permissões restritas e recusa links simbólicos tanto para o backup quanto para a identidade. O caminho do arquivo de backup é escolhido pela data de modificação mais recente, não pelo nome.

## Segurança da restauração

1. Antes de qualquer restauração, `backupctl` escolhe um nome `pncp-restore-check-<timestamp>-<aleatório>`, verifica colisão do volume PostgreSQL e chama `scripts/restore-isolated.sh`.
2. O script existente recusa objeto preexistente no banco de destino, descriptografa e faz `pg_restore` com transação; executa migrations/grants somente nesse projeto.
3. O postflight verifica `015_auth_capability_rls.up.sql`, `pncp_app` não-superuser/NOBYPASSRLS e RLS forçada das tabelas com `company_id`.
4. `backupctl` exibe tempo de restauração em segundos e o nome do projeto, sem mostrar dados ou conteúdo da identidade. Sem `--cleanup`, preserva o volume para inspeção. Com `--cleanup`, usa `docker compose -p <projeto-gerado> down --volumes` apenas **depois do postflight aprovado**. Se falhar, o volume fica preservado para análise e não há limpeza automática.
5. Não há deploy, cutover, downgrade de schema ou ativação do worker. O banco ativo permanece sob outro projeto Compose.

O comando **não mede o RTO ponta a ponta** de um incidente, não prova que o último backup recupera todos os dados relevantes (RPO) e não valida cópia externa, PITR ou recuperação após perda física do host. Esses critérios continuam exigindo aceite e evidências reais na [issue #25](https://github.com/fernandosam/pncp-opportunity-agent/issues/25).

**Armazenamento atual:** backups age locais, janela de até 7 dias, scheduler diário às 03:30 UTC. Se o host/disco for perdido, arquivos somente locais também se perdem. Enviar cópias criptografadas para outro destino é uma decisão de custo, acesso e retenção separada.

## Testes e limite da evidência

`bash tests/backupctl.test.sh` testa encaminhamento dos quatro comandos, escolha do backup mais recente, bloqueio de arquivos inseguros, chave ausente, limpeza apenas sob autorização, colisão de projeto e preservação após falha. Usa comandos e restauração simulados: um PASS aqui **não prova que o arquivo age real é restaurável**.

Para comprovar a restauração na V1, executar `./backupctl verify --identity <arquivo>` no host do responsável, observar o postflight real, registrar duração e resultado na #25 sem compartilhar chaves, dumps, dados dos tenants ou conteúdo de `.env`. A execução do GitHub Actions e assinatura de produção continuam gates separados.
