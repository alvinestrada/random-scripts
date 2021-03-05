/*
Description: This script will fetch ALL 
*/
DECLARE @FOLDER_NAME NVARCHAR(128);
DECLARE @SOURCE_ENVIRONMENT NVARCHAR(128);

SET @FOLDER_NAME  = N'CRM'
SET @SOURCE_ENVIRONMENT  = N'DEV'

SELECT ',(' +
    '''' + v.[name] + '''' + ',' +
    '''' + CONVERT(NVARCHAR(1024),ISNULL(v.[value], N'<VALUE GOES HERE>')) +
    ''''  + ',' +
    '''' + v.[description] + '''' +
    ')' ENVIRONMENT_VARIABLES
FROM [SSISDB].[catalog].[environments] e
JOIN [SSISDB].[catalog].[folders] f
   ON e.[folder_id] = f.[folder_id]
JOIN [SSISDB].[catalog].[environment_variables] v
   ON e.[environment_id] = v.[environment_id]
WHERE e.[name] = ISNULL(@SOURCE_ENVIRONMENT, e.[name])
  AND f.[name] = ISNULL(@FOLDER_NAME, f.[name])
ORDER BY v.[name];	