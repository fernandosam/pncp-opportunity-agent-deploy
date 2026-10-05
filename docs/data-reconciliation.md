# Reconciliação — novo ambiente Docker, sem importação

## Decisão do usuário

Solicitação explícita: **“Fazer a reconciliação dos dados. Não precisa importar.”**

O Docker é tratado como ambiente novo. Importação/cutover do histórico Railway deixou de ser requisito para este ambiente. Não foram importados registros, criadas empresas/perfis fictícios, alterados dados do banco antigo, apagados volumes nem liberadas reservas. Nenhum worker/provedor foi ativado.

## Banco Docker — baseline anterior ao provisionamento

Snapshot read-only da reconciliação inicial. Posteriormente o usuário autorizou cadastrar empresa/responsável e reutilizar somente o perfil comercial: [onboarding atual](local-onboarding.md). Os números vazios abaixo descrevem o baseline, não o estado posterior ao cadastro.

`./scripts/reconcile.sh` lê somente metadados/contagens, em REPEATABLE READ/READ ONLY, sem payloads, tokens, e-mails ou senhas.

| Verificação | Resultado |
|---|---:|
| Migrations aplicadas | 14 |
| Tabelas public | 21 |
| Tabelas com RLS | 19 |
| Constraints não validadas | 0 |
| Tabelas de negócio com registros | 0 |
| Ledger LLM / custo desconhecido | 0 / 0 |
| Compromisso local LLM | US$ 0 |

As 14 linhas de `schema_migrations` são metadados de instalação, não dados importados. As demais 20 tabelas estão vazias: sem tenants/responsáveis/perfis, oportunidades/documentos, avaliações/claims/jobs, briefings/outbox, feedback/sessões ou snapshots.

Runtime `pncp_app`: superuser=false, bypass_rls=false, escrita do journal de migrations=false. Web/worker compartilham banco, CA e segredo de feedback forte. Allowlist do worker vazia, chaves Groq/Resend vazias. Banco/web healthy; health ok/readiness ready. Smoke TLS obrigatório/hostname inválido/RLS e worker NODE_ENV=test passou sem chamadas externas.

## Histórico Railway — reconciliação das evidências disponíveis, não consulta atual

A origem está indisponível pelo trial expirado. Os valores abaixo são do último postflight privado bem-sucedido, anterior à indisponibilidade; não são uma leitura ao vivo nem confirmação de quitação do provedor.

| Último estado conhecido | Resultado |
|---|---:|
| Perfis comerciais | 1 |
| Oportunidades | 10 |
| Avaliações | 6 (2 anteriores + 4 reais v3) |
| Briefings / outbox | 0 / 0 |
| Precision snapshots | 1, precision=null/amostra insuficiente |
| Job 2026-10-02 | COMPLETED, GENERATE |
| Registros do ledger desse ensaio | 8 |

Ledger do ensaio: três FAILED com custo desconhecido, reserva US$ 0,05 cada (**US$ 0,15 preservados**); um diagnóstico SUCCEEDED US$ 0,000074; quatro interpretações SUCCEEDED US$ 0,001988 / 0,000520 / 0,000218 / 0,000160. Soma conhecida no ledger **US$ 0,002960**; compromisso conservador **US$ 0,152960**. Considerando precisão original do diagnóstico: aprox. US$ 0,1529601, saldo do teto antigo US$ 0,20 aprox. **US$ 0,0470399**.

Uso das quatro interpretações: 14.964 tokens de entrada / 1.261 saída, custo estimado US$ 0,002886. Seis respostas HTTP Groq, quatro avaliações NOT_RECOMMENDED; sem briefing elegível/e-mail. ZERO novas chamadas nesta reconciliação. Os três custos desconhecidos continuam desconhecidos; não foram tratados como zero ou reembolsados.

## Diferenças explicadas e conclusão

Diferença de registros Railway→Docker é **intencional**, pela decisão de iniciar sem importação, não uma perda causada por restore. O original/evidências privadas continuam preservados. O histórico não foi reconstituído por dados fabricados.

O banco Docker zerado **não cancela o gasto/compromisso anterior**. O teto diário configurado no worker não autoriza reset do ensaio, consumo recorrente ou nova verba. Este ambiente ainda não tem empresa/responsável/perfil real: cadastrar dados reais e configurar allowlist/credenciais/orçamento autorizado são os próximos pré-requisitos do worker; importação não é mais um bloqueio.

Reconciliação concluída quanto à consistência local e evidências históricas disponíveis. Conciliação financeira final dos custos desconhecidos com o provedor não foi possível e permanece aberta, sem liberação de reservas. Produção/§10 continuam sem aprovação humana.
