/* ============================================================
   01_criar_schemas.sql
   Cria os schemas usados pelos scripts seguintes:
   - stg: tabelas brutas (criadas pelo 02_load_staging.py) e tabelas *_limpa (02_limpeza_stg.sql)
   - dw:  dimensões e fatos do modelo estrela (03_dimensoes.sql e 04_fatos.sql)
   Pode ser executado várias vezes.
   ============================================================ */

IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
GO

IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw');
GO
