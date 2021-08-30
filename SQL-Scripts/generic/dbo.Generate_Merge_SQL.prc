IF OBJECT_ID('dbo.Generate_Merge_SQL') IS NOT NULL
BEGIN
	DROP PROCEDURE dbo.Generate_Merge_SQL
	PRINT 'DROP PROCEDURE dbo.Generate_Merge_SQL'
END
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[Generate_Merge_SQL]
         @source_db_name     SYSNAME   
		,@source_table_name  SYSNAME 
		,@source_schema_name SYSNAME
		,@source_key_column  SYSNAME = NULL
		,@target_table_name  SYSNAME = NULL			-- Not in use atm
		,@target_schema_name SYSNAME = NULL			-- Not in use atm
		,@target_key_column  SYSNAME = NULL			-- Not in use atm
		,@is_computed_column BIT     = 0
		,@debug_mode		 BIT     = 1
AS
-- =============================================
-- Author:      Alvin Estrada
-- Create date: initial
-- Description: This script will generate a MERGE SQL store procedure
-- License    : MIT 
-- =============================================
BEGIN
   
	--SET NOCOUNT ON added to prevent extra result sets from
	--interfering with SELECT statements.
   SET NOCOUNT ON;

	DECLARE @merge_statement		NVARCHAR(MAX)
	DECLARE @current_column_id		INT,
			@current_column_name	SYSNAME,
			@current_column_type    VARCHAR(1000),
			@column_list			NVARCHAR(MAX),
			@source_column_list		NVARCHAR(MAX),
			@update_set				NVARCHAR(MAX),
			@has_identity			BIT,
			@get_value				NVARCHAR(MAX),
			@values					NVARCHAR(MAX)
	
	DECLARE @tab_columns TABLE (column_id int, column_name SYSNAME)
	DECLARE @sql		 NVARCHAR(MAX)
	SELECT  @current_column_id		= NULL,
			@current_column_name	= NULL,
			@current_column_type    = NULL,
			@column_list			= NULL,
			@update_set				= NULL,
			@has_identity			= NULL,
			@get_value				= NULL,
			@values					= NULL

	-- lets start with the first column
	SET @sql = N' SELECT ORDINAL_POSITION,  COLUMN_NAME  
	               FROM ' + @source_db_name + '.INFORMATION_SCHEMA.COLUMNS WITH (NOLOCK)
				  WHERE TABLE_NAME		    = ''' + @source_table_name  + N''' 
                    AND TABLE_SCHEMA		= ''' + @source_schema_name + N''' 
				ORDER BY ORDINAL_POSITION'

	IF @debug_mode = 1
	    PRINT 'Current ID: ' + @sql
				
    INSERT @tab_columns EXECUTE (@sql)


	 SELECT	@current_column_id = min(column_id)
      FROM	@tab_columns

	 if @debug_mode = 1
	    PRINT 'Current ID: ' + CAST(ISNULL(@current_column_id, '')  AS VARCHAR(100))

	-- loopy loop
	WHILE @current_column_id IS NOT NULL
	BEGIN
	
		SELECT @current_column_name = QUOTENAME(COLUMN_NAME)
		  FROM @tab_columns
		 WHERE column_id = @current_column_id

		IF @debug_mode = 1
			PRINT 'Processing column ' + @current_column_name

		-- skip if current column are computed field
		-- Should I skip
		/*
		IF (SELECT COLUMNPROPERTY( OBJECT_ID(QUOTENAME(@source_schema_name) + '.' + @source_table_name),SUBSTRING(@current_column_name,2,LEN(@current_column_name) - 2),'IsComputed')) = 1 
		BEGIN
	 		-- GOTO SKIP_COLUMN					
			SET @is_computed_column = 1
		END
		ELSE 
			SET @is_computed_column = 0
        */

		IF @is_computed_column != 1
		BEGIN
			SET @column_list = ISNULL(@column_list + ', ' + char(10), N'') + @current_column_name
			SET @source_column_list = ISNULL(@source_column_list + ', ' + char(10), N'') + N'src.' + @current_column_name
		END

		-- Check if the current column is an identity field
		IF (SELECT COLUMNPROPERTY( OBJECT_ID(QUOTENAME(@source_schema_name) + '.' + @source_table_name),SUBSTRING(@current_column_name,2,LEN(@current_column_name) - 2),'IsIdentity')) = 1 
		BEGIN
			SET @has_identity = 1		
		END
		ELSE IF NOT EXISTS ( SELECT  NULL
							   FROM sys.indexes AS ind		
						 INNER JOIN sys.index_columns AS indcol
								 ON ind.object_id = indcol.object_id AND 
									ind.index_id = indcol.index_id
							  WHERE ind.is_primary_key = 1
								AND ind.object_id = OBJECT_ID(QUOTENAME(@source_schema_name) + '.' + QUOTENAME(@source_table_name))
								AND indcol.column_id = @current_column_id
			)
		BEGIN
			-- If column is not IDENTITY and not part of the PK, then concatenate it to UPDATE SET clause
			SET @update_set = ISNULL(@update_set + N', ' + char(10), N'') + N'tar.' + @current_column_name + N' = src.' + @current_column_name
		END

		SKIP_COLUMN:  -- GOTO label
			 SELECT	@current_column_id = min(column_id)
               FROM	@tab_columns
			  WHERE column_id > @current_column_id
	-- end of while loop
	END;  

	SET @merge_statement = N'
IF OBJECT_ID(''dbo.Merge_' + @source_table_name + N''') IS NOT NULL
BEGIN
	DROP PROCEDURE dbo.Merge_' + @source_table_name + N'
	PRINT ''DROP PROCEDURE dbo.Merge_' + @source_table_name + N'''
END
GO

PRINT ''CREATE PROCEDURE dbo.Merge_' + @source_table_name + N''';
GO

CREATE PROCEDURE dbo.Merge_' + @source_table_name + N' @batch_id INT
AS
DECLARE @data_load TABLE (
	load_target_table VARCHAR(150),
	load_action		  VARCHAR(200)
)
MERGE [source_integration].' + QUOTENAME(@source_schema_name) + N'.' + QUOTENAME(@source_table_name)   + N' AS tar
USING [etl].' + QUOTENAME(@source_schema_name) + N'.' + QUOTENAME(@source_table_name)  + N'AS src
	ON ( tar.' + @source_key_column + N' = src.' + @source_key_column + N')
-- UPDATE
WHEN MATCHED AND tar.HASHVALUE != src.HASHVALUE THEN 
UPDATE SET
	' + @update_set + N'
-- INSERT 
WHEN NOT MATCHED BY TARGET THEN 
INSERT (' + @column_list + N' )
VALUES (' + @source_column_list + N')
OUTPUT ''[source_integration].' + QUOTENAME(@source_schema_name) + N'.' + QUOTENAME(@source_table_name) + N''', $action
INTO @data_load;

--
-- Use for audit logs
--
INSERT INTO Data_Load_Log ( batch_id, load_target_table, total_inserted_rows, total_updated_rows)
SELECT @batch_id,
		load_target_table,	
		sum(case when load_action = ''INSERT'' THEN 1 ELSE 0 END) AS total_inserted,
		sum(case when load_action = ''UPDATE'' THEN 1 ELSE 0 END) AS total_updated
FROM @data_load
GROUP BY load_target_table, load_action
GO

IF OBJECT_ID(''dbo.Merge_Tenders'') IS NOT NULL
	PRINT ''Successfully created dbo.Merge_Tenders...''
GO

/*
-- How to test
DECLARE @batch_id INT
select @batch_id = max(batch_id) from etl.dbo.Data_Load_Log
truncate table [source_integration].' + QUOTENAME(@source_schema_name) + N'.' + QUOTENAME(@source_table_name)   + N' 
EXEC dbo.Merge_' + @source_table_name + N'

*/
'
	-- Print long text
	-- Since SQL have issue with max limit, lets break-down the display of the text
	DECLARE 
		@current_start	int,
		@total_len		int,
		@curr_id		int,
		@curr_msg		nvarchar(max)

	SELECT
		@current_start = 1,
		@total_len	   = LEN(@merge_statement);

	WHILE @current_start < @total_len
	BEGIN
		-- Find next linebreak
		SET @curr_id = CHARINDEX(CHAR(10), @merge_statement, @current_start)
	
		-- If linebreak found
		IF @curr_id > 0
		BEGIN
			-- Trim line from message, print it and increase index
			SET @curr_msg = SUBSTRING(@merge_statement, @current_start, @curr_id - @current_start - 1)
			PRINT @curr_msg
			SET @current_start = @curr_id + 1
		END
		ELSE
		BEGIN
			-- Print last line
			SET @curr_msg = SUBSTRING(@merge_statement, @current_start, @total_len)
			PRINT @curr_msg
			SET @current_start = @total_len
		END
	END
	   SELECT @merge_statement 

END;
GO

IF OBJECT_ID('dbo.Generate_Merge_SQL') IS NOT NULL
BEGIN
	PRINT 'Successfully CREATED PROCEDURE dbo.Generate_Merge_SQL'
END
GO

