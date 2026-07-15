USE [Analysen]
GO

CREATE OR ALTER PROC [dbo].[Logging]

	@LogID					AS BigInt output
,	@LogTableName			AS nVarChar(200)	= ''
,	@LogTableTime			AS DateTime2		= NULL
,	@LogTableProcess		AS nVarChar(200)	= ''			-- Update/Join...
,	@LogTableProcessMode	AS nVarChar(50)		= ''			-- FULL/DELTA/TEST/PREPARING
,	@LogTableProcessStatus	AS nVarChar(20)		= 'PROCESS'		-- PROCESS/FINISHED/ERROR

,	@LogStep				AS nVarChar(20)		= ''
,	@LogStepText			AS nVarChar(500)	= ''
,	@LogStepStart			AS DateTime2		= NULL
,	@LogStepEnd				AS DateTime2		= NULL
,	@LogStepSQL				AS VarChar(max)		= ''
,	@LogStepSQL1			AS VarChar(max)		= ''
,	@LogStepSQL2			AS VarChar(max)		= ''
,	@LogStepSQL3			AS VarChar(max)		= ''
,	@LogStepSQL4			AS VarChar(max)		= ''
,	@LogStepSQL5			AS VarChar(max)		= ''
,	@LogStepSQL6			AS VarChar(max)		= ''
,	@LogStepSQL7			AS VarChar(max)		= ''
,	@LogStepSQL8			AS VarChar(max)		= ''
,	@LogStepSQL9			AS VarChar(max)		= ''
,	@LogStepSQL10			AS VarChar(max)		= ''
,	@LogStepRows			AS BigInt			= 0
,	@LogStepStatus			AS nVarChar(200)	= 'FINISHED'	-- PROCESS/FINISHED/ERROR
,	@LogStepError			AS Int				= NULL			-- Error-Code
,	@LogStepErrorText		AS nVarChar(4000)	= ''			-- Error-Text

,	@LogTime				AS DateTime2		= NULL
,	@LogUser				AS nVarChar(100)	= NULL

,	@SQL_TableLoggingString			AS nVarChar(299)	= ''
,	@SQL_TableRelationTreeString	AS nVarChar(299)	= ''

AS
BEGIN

	DECLARE @LogStepStart0				AS DateTime2
	DECLARE @LogStepDuration_AVG		AS nVarChar(8)
	DECLARE @LogStepDuration_Quo		AS Decimal(10,4)
	DECLARE @LogStepDuration_AVG_cum	AS nVarChar(8)
	DECLARE @SQL						AS nVarChar(max)	= ''
	DECLARE @TreeStatusText				AS nVarChar(20)		= ''

/*
Set @Log*-Parameter, if unknown
*/

	If @LogUser is null
		Set @LogUser = SUSER_NAME()

	If @LogTime is null
		Set @LogTime = Getdate()

	If Len(@LogID) = 0 or @LogID is null
		BEGIN
			SET @SQL = CONCAT('SELECT @LogID = (SELECT ISNULL(MAX(LogID), 0) + 1 AS NewLogID FROM ', @SQL_TableLoggingString, ')')
			EXEC sp_EXECuteSQL @SQL, N'@LogID BigInt OUT', @LogID OUT

			SET @SQL = ''
		END

	If Len(@LogID) = 0 or @LogID is null
		Set @LogID = 1

	If @LogStepEnd is null
		Set @LogStepEnd = Getdate()

	If @LogStepStart is null
		If @LogTableProcessStatus = 'FINISHED' 
			BEGIN
				SET @SQL = CONCAT('SELECT @LogStepStart = (SELECT ISNULL(MIN(LogStepStart), getdate()) AS LogStepStart FROM ', @SQL_TableLoggingString, ' WHERE LogID = ', @LogID, ')')
				EXEC sp_EXECuteSQL @SQL, N'@LogStepStart DateTime2 OUT', @LogStepStart OUT

				SET @SQL = ''
			END
		ELSE
			BEGIN
				SET @SQL = CONCAT('SELECT @LogStepStart = (SELECT ISNULL(MAX(LogStepEnd), getdate()) AS LogStepStart FROM ', @SQL_TableLoggingString, ' WHERE LogID = ', @LogID, ')')
				EXEC sp_EXECuteSQL @SQL, N'@LogStepStart DateTime2 OUT', @LogStepStart OUT

				SET @SQL = ''
			END

	If @LogTableTime is null
		BEGIN
			SET @SQL = CONCAT('SELECT @LogTableTime = (SELECT ISNULL(MAX(LogTableTime), getdate()) AS LogTableTime FROM ', @SQL_TableLoggingString, ' WHERE LogID = ', @LogID, ')')
			EXEC sp_EXECuteSQL @SQL, N'@LogTableTime DateTime2 OUT', @LogTableTime OUT

			SET @SQL = ''
		END

	If @LogTableName is null or Len(@LogTableName) = 0
		BEGIN
			SET @SQL = CONCAT('SELECT @LogTableName = (SELECT DISTINCT FIRST_VALUE(LogTableName) OVER (PARTITION BY LogID ORDER BY LogStepEnd DESC) AS Val FROM ', @SQL_TableLoggingString, ' WHERE LogID = ', @LogID, ')')
			EXEC sp_EXECuteSQL @SQL, N'@LogTableName nVarChar(200) OUT', @LogTableName OUT

			SET @SQL = ''
		END

	If @LogTableProcess is null or Len(@LogTableProcess) = 0
		BEGIN
			SET @SQL = CONCAT('SELECT @LogTableProcess = (SELECT DISTINCT FIRST_VALUE(LogTableProcess) OVER (PARTITION BY LogID ORDER BY LogStepEnd DESC) AS Val FROM ', @SQL_TableLoggingString ,' WHERE LogID = ', @LogID, ')')
			EXEC sp_EXECuteSQL @SQL, N'@LogTableProcess nVarChar(200) OUT', @LogTableProcess OUT

			SET @SQL = ''
		END

/*
Set @LogTableProcessMode
*/

	If @LogTableProcessMode is null or Len(@LogTableProcessMode) = 0
		BEGIN
			SET @SQL = CONCAT('SELECT @LogTableProcessMode = (SELECT DISTINCT FIRST_VALUE(LogTableProcessMode) OVER (PARTITION BY LogID ORDER BY LogStepEnd DESC) AS Val FROM ', @SQL_TableLoggingString, ' WHERE LogID = ', @LogID, ')')
			EXEC sp_EXECuteSQL @SQL, N'@LogTableProcessMode nVarChar(50) OUT', @LogTableProcessMode OUT

			SET @SQL = ''
		END

	If Upper(left(@LogTableProcessMode, 1)) = 'T'
		Set @LogTableProcessMode = 'TEST'

	If Upper(left(@LogTableProcessMode, 1)) = 'D'
		Set @LogTableProcessMode = 'DELTA'

	If Upper(left(@LogTableProcessMode, 1)) = 'F'
		Set @LogTableProcessMode = 'FULL'

	If Upper(left(@LogTableProcessMode, 2)) = 'FN'
		Set @LogTableProcessMode = 'FULL'

	If Upper(@LogTableProcessMode) = 'P'
		Set @LogTableProcessMode = 'PREPROCESSING'

	If Upper(left(@LogTableProcessMode, 4)) = 'PREP'
		Set @LogTableProcessMode = 'PREPROCESSING'

	If Upper(left(@LogTableProcessMode, 4)) = 'MAIN'
		Set @LogTableProcessMode = 'MAINPROCESSING'

	If Upper(left(@LogTableProcessMode, 4)) = 'POST'
		Set @LogTableProcessMode = 'POSTPROCESSING'

/*
Set additional @Log*-Parameter
*/

	If @LogTableProcessStatus is null or Len(@LogTableProcessStatus) = 0
		BEGIN
			SET @SQL = CONCAT('SELECT @LogTableProcessStatus = (SELECT DISTINCT FIRST_VALUE(LogTableProcessStatus) OVER (PARTITION BY LogID ORDER BY LogStepEnd DESC) AS Val FROM ', @SQL_TableLoggingString, ' WHERE LogID = ', @LogID, ')')
			EXEC sp_EXECuteSQL @SQL, N'@LogTableProcessStatus nVarChar(20) OUT', @LogTableProcessStatus OUT

			SET @SQL = ''
		END

	If @LogStepError is null
		Set @LogStepError = 0

	If @LogStepError <> 0 and @LogStepError <> 99993
		Begin
			Set @LogStepStatus = 'ERROR'
			Set @LogTableProcessStatus = 'ERROR'
			If Len(@LogStepErrorText) < 3
				BEGIN
					SET @SQL = CONCAT('SELECT @LogStepErrorText = ISNULL((SELECT Text FROM .sys.messages WHERE message_id = ', @LogStepError, ' AND language_id = 1031), '''')')
					EXEC SP_ExecuteSQL @SQL, N'@LogStepErrorText nVarChar(4000) OUT', @LogStepErrorText OUT

					SET @SQL = ''
				END
		End

	If @LogStep = 'END' and (DATALENGTH(@LogStepSQL) = 0 or @LogStep is null)
		BEGIN
			SET @SQL = CONCAT('SELECT @LogStepSQL = ISNULL((SELECT LogStepSQL FROM ', @SQL_TableLoggingString, ' WHERE LogID = ', @LogID, ' AND LogStep = ''START''), '''')')
			EXEC sp_EXECuteSQL @SQL, N'@LogStepSQL nVarChar(max) OUT', @LogStepSQL OUT

			SET @SQL = ''
		END

	SET @SQL = CONCAT('SELECT @LogStepStart0 = (SELECT ISNULL(MIN(LogStepStart), getdate()) AS LogStepStart FROM ', @SQL_TableLoggingString, ' WHERE LogID = ', @LogID, ')')
	EXEC sp_EXECuteSQL @SQL, N'@LogStepStart0 DateTime2 OUT', @LogStepStart0 OUT

	SET @SQL = ''

	SET @SQL =	CONCAT('SELECT @LogStepDuration_AVG =	ISNULL(
															(
																SELECT
																	CONVERT(VarChar(8), DATEADD(SECOND, AVG(DATEDIFF(SECOND, LogStepStart, LogStepEnd)), ''19000101''), 8) AS LogStepDuration
																FROM ', @SQL_TableLoggingString, '
																WHERE LogTableName = ''', @LogTableName, '''
																AND LogTableProcess = ''', @LogTableProcess, '''
																AND LogStep = ''', @LogStep, '''
																AND LogTableProcessMode = ''', @LogTableProcessMode, '''
																AND LogStepStatus = ''FINISHED''
															)
														,	0
														)'
				)

	EXEC sp_EXECuteSQL @SQL, N'@LogStepDuration_AVG nVarChar(8) OUT', @LogStepDuration_AVG OUT

	SET @SQL = ''

	SET @SQL =	CONCAT('SELECT
							@LogStepDuration_AVG_cum =	ISNULL(
															CONVERT(VarChar(8), DATEADD(SECOND, AVG(DATEDIFF(SECOND, CAST('''' AS DateTime2), CAST(t2.LogStepDuration_cum AS DateTime2))), ''19000101''), 8)
														,	0
														)
						,	@LogStepDuration_Quo =	ISNULL(
														CASE
															WHEN
																AVG(DATEDIFF(SECOND, CAST('''' AS DateTime2), CAST(t2.LogStepDuration_cum AS DateTime2))) > 0
															THEN
																CAST(CAST(AVG(DATEDIFF(SECOND ,CAST('''' AS DateTime2), CAST(t1.LogStepDuration_cum AS DateTime2))) AS Float) / CAST(AVG(DATEDIFF(SECOND, CAST('''' AS DateTime2), CAST(t2.LogStepDuration_cum AS DateTime2))) AS Float) AS Decimal(10,4))
															ELSE
																0
														END
													,	0
													)
							FROM ', @SQL_TableLoggingString, ' AS t1
							INNER JOIN ', @SQL_TableLoggingString, ' AS t2
							ON t1.LogID = t2.LogID
							AND t2.LogStep = ''END''
							AND t2.LogTableProcessMode = ''', @LogTableProcessMode, '''
							AND t1.LogTableName = ''', @LogTableName, '''
							AND t1.LogStep = ''', @LogStep, ''''
				)

	EXEC sp_EXECuteSQL @SQL, N'
		@LogStepDuration_AVG_cum AS nVarChar(8) OUT
	,	@LogStepDuration_Quo AS Decimal(10,4) OUT'
	,	@LogStepDuration_AVG_cum = @LogStepDuration_AVG_cum OUT
	,	@LogStepDuration_Quo = @LogStepDuration_Quo OUT

	SET @SQL = ''

	If left(@LogTableProcessStatus, 7) = 'PROCESS'
		Set @LogTableProcessStatus = Concat(@LogTableProcessStatus,' (',@LogStepDuration_Quo*100,'%)')

/* --> wir kennen @SQL_TableTargetDB eigentlich nicht
	If @LogTableProcessStatus = 'FINISHED' and isnull(@LogStepRows, 0) = 0
		BEGIN
			SET @SQL = CONCAT('SELECT @LogStepRows = ISNULL((SELECT MAX(Rows) AS Rowcount FROM ', @SQL_TableTargetDB, '.sys.partitions WHERE object_id = OBJECT_ID(''', @LogTableName, ''', ''U'')), 0)')
			EXEC sp_EXECuteSQL @SQL, N'@LogStepRows BigInt OUT', @LogStepRows OUT

			SET @SQL = ''
		END
*/

/*
Write into Logging-Table
*/

	SET @SQL = CONCAT('
		INSERT INTO ', @SQL_TableLoggingString, '

		SELECT
			'	, @LogID													,	' AS LogID
		,	'''	, @LogTableName												, ''' AS LogTableName
		,	'	, ISNULL(OBJECT_ID(@LogTableName, 'U'), 0)					,	' AS LogObjectID
		,	'''	, CONVERT(nVarChar, @LogTableTime,126)						, ''' AS LogTableTime
		,	'''	, @LogTableProcess											, ''' AS LogTableProcess
		,	'''	, @LogTableProcessMode										, ''' AS LogTableProcessMode
		,	'''	, @LogTableProcessStatus									, ''' AS LogTableProcessStatus

		,	'''	, @LogStep													, ''' AS LogStep
		,	'''	, REPLACE(@LogStepText, '''', '''''')						, ''' AS LogStepText
		,	'''	, CONVERT(nVarChar, @LogStepStart,126)						, ''' AS LogStepStart
		,	'''	, CONVERT(nVarChar, @LogStepEnd,126)						, ''' AS LogStepEnd

		,	'''	, CONVERT(VarChar(8), DATEADD(SECOND, DATEDIFF(SECOND, @LogStepStart, @LogStepEnd), '19000101'), 8)		, ''' AS LogStepDuration
		,	'''	, CONVERT(VarChar(8), DATEADD(SECOND, DATEDIFF(SECOND, @LogStepStart0, @LogStepEnd), '19000101'), 8)	, ''' AS LogStepDuration_cum

		,	'''	, REPLACE(@LogStepSQL + @LogStepSQL1 + @LogStepSQL2 + @LogStepSQL3 + @LogStepSQL4 + @LogStepSQL5 + @LogStepSQL6 + @LogStepSQL7 + @LogStepSQL8 + @LogStepSQL9 + @LogStepSQL10, '''', '''''')	, ''' AS LogStepSQL

		,	'	, ISNULL(@LogStepRows, 0)	,	' AS LogStepRows
		,	'''	, @LogStepStatus			, ''' AS LogStepStatus
		,	'''	, @LogStepError				, ''' AS LogStepError
		,	'''	, @LogStepErrorText			, ''' AS LogStepErrorText

		,	'''	, CONVERT(nVarChar, CAST(getdate() AS DateTime2), 126)	, ''' AS LogTime
		,	'''	, @LogUser												, ''' AS LogUser'
	)

	EXEC(@SQL)

	SET @SQL = ''

	IF @LogTableProcessStatus = 'FINISHED'
		BEGIN
			SET @SQL = CONCAT('
				UPDATE ', @SQL_TableLoggingString, '

				SET
					LogObjectID = ', ISNULL(OBJECT_ID(@LogTableName, 'U'), 0), '
				FROM ', @SQL_TableLoggingString, '
				WHERE LogID = ', @LogID
			)

			EXEC(@SQL)

			SET @SQL = ''
		END

/*
Update column "StatusText" in table "TabTree"
*/

	IF (@LogTableProcessStatus = 'START' OR LEFT(@LogTableProcessStatus, 7) = 'PROCESS') AND (@LogStepError = 0 OR @LogStepError = 99993) -- wirklich jedes Mal bei 'PROCESS'-Log aktualisieren? % in "StatusText" sind nicht wichtig
		BEGIN
			SET @SQL = CONCAT('
				UPDATE ', @SQL_TableRelationTreeString, '

				SET
					StatusText		= ''Processing (', @LogStepDuration_Quo * 100, '%)''
				,	LoadingMethode	= ''', @LogTableProcessMode, '''
				,	LogID			= '  , @LogID, '
				,	LoggingTable	= ''', @SQL_TableLoggingString, '''
				WHERE TargetObjectID = ', ISNULL(OBJECT_ID(@LogTableName, 'U'), 0)
			)

			EXEC(@SQL)

			SET @SQL = ''
		END

	IF @LogTableProcessStatus = 'FINISHED' AND (@LogStepError = 0 OR @LogStepError = 99993)
		BEGIN
			SET @SQL = CONCAT('
				UPDATE ', @SQL_TableRelationTreeString, '

				SET
					StatusText		= ''valid''
				,	LoadingMethode	= ''', @LogTableProcessMode, '''
				,	LogID			= '  , @LogID, '
				,	LoggingTable	= ''', @SQL_TableLoggingString, '''
				WHERE TargetObjectID = ', ISNULL(OBJECT_ID(@LogTableName, 'U'), 0)
			)

			EXEC(@SQL)

			SET @SQL = ''
		END

	IF @LogStepError <> 0 AND @LogStepError <> 99993
		BEGIN
			SET @SQL = CONCAT('
				UPDATE ', @SQL_TableRelationTreeString, '

				SET
					StatusText		= ''valid (loadingerror)''
				,	LoadingMethode	= ''', @LogTableProcessMode, '''
				,	LogID			= '  , @LogID, '
				,	LoggingTable	= ''', @SQL_TableLoggingString, '''
				WHERE TargetObjectID = ', ISNULL(OBJECT_ID(@LogTableName, 'U'), 0)
			)

			EXEC(@SQL)

			SET @SQL = ''
		END

	IF @LogTableProcessStatus = 'FINISHED' AND @LogStepError <> 99993 AND @LogTableProcessMode = 'FULL'
		SET @TreeStatusText = 'invalid'

	IF @LogTableProcessStatus = 'FINISHED' AND @LogStepError <> 99993 AND @LogTableProcessMode = 'DELTA'
		SET @TreeStatusText = 'valid (outdated)'

	IF LEN(@TreeStatusText) > 0
		BEGIN
			SET @SQL = CONCAT('
				WITH Baum AS (
					SELECT
						CAST(CONCAT(t1.TargetTableDB, ''.'', t1.TargetTableSchema, ''.'', t1.TargetTableName) AS nVarchar(1000)) AS Pfad
					,	CONCAT(t1.TargetTableDB, ''.'', t1.TargetTableSchema, ''.'', t1.TargetTableName) AS Tab
					,	1 AS Ebene
					,	t1.TargetID
					,	t1.TargetUpdate
					,	t1.StatusText
					FROM ', @SQL_TableRelationTreeString, ' AS t1
					LEFT JOIN ', @SQL_TableRelationTreeString, ' AS t2
					ON t1.TargetTableDB = t2.SourceTableDB
					AND t1.TargetTableSchema = t2.SourceTableSchema
					AND t1.TargetTableName = t2.SourceTableName
					WHERE t2.SourceTableDB IS NULL

					UNION ALL

					SELECT
						CAST(CONCAT(t2.Pfad, ''|'', t1.SourceTableDB, ''.'', t1.SourceTableSchema, ''.'', t1.SourceTableName) AS nVarChar(1000)) AS Pfad
					,	CONCAT(t1.SourceTableDB, ''.'', t1.SourceTableSchema, ''.'', t1.SourceTableName) AS Tab
					,	t2.Ebene + 1 AS Ebene
					,	t1.TargetID
					,	t1.TargetUpdate
					,	t1.StatusText
					FROM ', @SQL_TableRelationTreeString, ' AS t1
					INNER JOIN Baum AS t2
					ON CONCAT(t1.TargetTableDB, ''.'', t1.TargetTableSchema, ''.'', t1.TargetTableName) = t2.Tab
				),

				Ergebnis AS (
					SELECT DISTINCT
						t1.Tab
					,	t2.VALUE AS RTab
					FROM Baum AS t1
					CROSS APPLY STRING_SPLIT(Pfad, ''|'') AS t2
					WHERE t1.Tab = ''', @LogTableName, '''
					AND t1.Tab != t2.VALUE
				)

				UPDATE ', @SQL_TableRelationTreeString, '

				SET
					StatusText = ''', @TreeStatusText, '''
				FROM ', @SQL_TableRelationTreeString, ' AS t1
				INNER JOIN Ergebnis AS t2
				ON CAST(CONCAT(t1.SourceTableDB, ''.'', t1.SourceTableSchema, ''.'', t1.SourceTableName) AS nVarChar(1000)) = t2.RTab' -- ist t1.Source... hier richtig?
			)

			EXEC(@SQL)

			SET @SQL = ''
		END

/*
Update column "TargetRows" and "TargetSpace" in table "TabTree"
*/

	IF @LogTableProcessStatus = 'FINISHED' AND @LogStepError <> 99993
		BEGIN
			SET @SQL = CONCAT('
				UPDATE ', @SQL_TableRelationTreeString, '

				SET
					TargetRows	= Zeilen
				,	TargetSpace	= Speicherplatz
				FROM (
					SELECT
						MAX(p.rows) AS Zeilen
					,	ISNULL(8 * SUM(CASE WHEN a.type != 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END),0.0) AS Speicherplatz
					FROM sys.tables AS tbl
					INNER JOIN sys.indexes AS i
					ON i.object_id = tbl.object_id
					INNER JOIN sys.partitions AS p
					ON p.object_id = i.object_id
					AND p.index_id = i.index_id
					INNER JOIN sys.allocation_units AS a
					ON a.container_id = p.partition_id
					WHERE tbl.object_id = ', ISNULL(OBJECT_ID(@LogTableName, 'U'), 0), '
				) AS t2
				WHERE TargetObjectID = ', ISNULL(OBJECT_ID(@LogTableName, 'U'), 0)
			)

			EXEC(@SQL)

			SET @SQL = ''
		END

/*
Print Parameters and return @LogID
*/

	PRINT 'ID: ' + CAST(@LogID AS nVarChar(20)) + ' Tablename: ' + @LogTableName
	PRINT 'Schritt: ' + @LogStep + ' -  ' + @LogStepText
	PRINT 'Start: ' + CONVERT(nVarChar(30), @LogStepStart, 113) + ' - Ende: ' + CONVERT(nVarChar(30), @LogStepEnd, 113)
	PRINT 'Dauer: ' + CONVERT(VarChar(8), DATEADD(SECOND, DATEDIFF(SECOND, @LogStepStart, @LogStepEnd), '19000101'), 8) + ' (Durchschnitt: ' + @LogStepDuration_AVG + ')'
	PRINT 'Dauer gesamt: ' + CONVERT(VarChar(8), DATEADD(SECOND, DATEDIFF(SECOND, @LogStepStart0, @LogStepEnd), '19000101'), 8) + ' (Durchschnitt: ' + @LogStepDuration_AVG_cum + ')'
	PRINT 'Status: ' + @LogStepStatus

	IF @LogStepError <> 0
		BEGIN
			PRINT 'Fehler-Code: ' + CONVERT(VarChar(8), @LogStepError)
			PRINT 'Fehler-Text: ' + @LogStepErrorText
		END

	PRINT '----------------------------------------------------------------------------------------------------'
	PRINT 'LogStepSQL:'
	PRINT ''
	PRINT @LogStepSQL
	PRINT @LogStepSQL1
	PRINT @LogStepSQL2
	PRINT @LogStepSQL3
	PRINT @LogStepSQL4
	PRINT @LogStepSQL5
	PRINT @LogStepSQL6
	PRINT @LogStepSQL7
	PRINT @LogStepSQL8
	PRINT @LogStepSQL9
	PRINT @LogStepSQL10
	PRINT ''
	PRINT '----------------------------------------------------------------------------------------------------'

	RETURN (@LogID)

END