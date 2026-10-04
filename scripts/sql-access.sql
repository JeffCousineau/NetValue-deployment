-- Run in the NetValue database as its configured Entra owner/admin.
-- Use client/application IDs for service principals (including managed identities), not object/principal IDs.
-- Resolve the app client ID: az ad sp show --id <web_app_principal_id> --query appId -o tsv
-- Deployment client ID is AZURE_CLIENT_ID from bootstrap.
DECLARE @app_id uniqueidentifier = 'REPLACE_WITH_WEB_APP_CLIENT_ID';
DECLARE @deployment_id uniqueidentifier = 'REPLACE_WITH_DEPLOYMENT_CLIENT_ID';
DECLARE @app_sid varbinary(16) = CONVERT(binary(16), @app_id);
DECLARE @deployment_sid varbinary(16) = CONVERT(binary(16), @deployment_id);
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'NetValue app' AND sid <> @app_sid)
    THROW 50000, 'Existing app user has a different identity.', 1;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'NetValue deployment' AND sid <> @deployment_sid)
    THROW 50000, 'Existing deployment user has a different identity.', 1;
DECLARE @statement nvarchar(300);
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'NetValue app')
BEGIN
    SET @statement = 'CREATE USER [NetValue app] WITH SID = ' + CONVERT(varchar(34), @app_sid, 1) + ', TYPE = E';
    EXEC (@statement);
END
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'NetValue deployment')
BEGIN
    SET @statement = 'CREATE USER [NetValue deployment] WITH SID = ' + CONVERT(varchar(34), @deployment_sid, 1) + ', TYPE = E';
    EXEC (@statement);
END
IF IS_ROLEMEMBER('db_datareader', 'NetValue app') <> 1
    ALTER ROLE db_datareader ADD MEMBER [NetValue app];
IF IS_ROLEMEMBER('db_datawriter', 'NetValue app') <> 1
    ALTER ROLE db_datawriter ADD MEMBER [NetValue app];
IF IS_ROLEMEMBER('db_datareader', 'NetValue deployment') <> 1
    ALTER ROLE db_datareader ADD MEMBER [NetValue deployment];
IF IS_ROLEMEMBER('db_datawriter', 'NetValue deployment') <> 1
    ALTER ROLE db_datawriter ADD MEMBER [NetValue deployment];
IF IS_ROLEMEMBER('db_ddladmin', 'NetValue deployment') <> 1
    ALTER ROLE db_ddladmin ADD MEMBER [NetValue deployment];
