USE Analysen
GO
--exec dbo.TabJoin
--ToDo: Hashabgleich in den Faktentabellen, zur Reduktion der betrachteten Zeiträume; Konfig und Ermittlung von @LastChangeOnDate 

Create or ALTER PROC dbo.TabJoin

	@TestLoop nvarchar(100)			='',	--> bspw. 'Top 100' für 100 Testdatensätze
	@DeltaDays as int				=7,		--> Delta-Load beinhaltet n volle Tage 
	@FullloadYears as int			=5,		--> Jahre die als Fullload geladen werden sollen, 0=Delta-Load
	@Ladeverfahren as nvarchar(2)	='F',	--> Wenn 'F' dann Fulload, wenn 'D' dann Deltaload, Sonst entscheidet das Skript automatische über das Ladeverfahren anhand der Einstellungen
	@TEMPPraefix as nvarchar(100)	='New',	--> 'New' wird eine neue TempID für alle Temptabellen vergeben
	@DaysToFullLoad int				=7,		--> Aller wieviel Tage soll ein Fullload durchgeführt werden?
	@TEMPLoeschen as int			=1,		--> 1=Tempdateien werden gelöscht	
	@MaxDelay	as bigint			=0,		--> Maximale Verzögerung des letzten Aktualisierung einer Quelltabelle in Minuten. Insofern 0 oder negative Zahlen verwendet werden, bezieht sich die Verzögerung auf Tage. (0 die Aktualisierung muss von heute sein, -1 die Aktualisierung muss von gestern sein)
	@LastChangeOnDate as int		=1,

	@SQL_Table1_ID as nvarchar(299)				='',
	@SQL_Table2_ID as nvarchar(299)				='',
	@SQL_Table3_ID as nvarchar(299)				='',
	@SQL_Table4_ID as nvarchar(299)				='',
	@SQL_Table5_ID as nvarchar(299)				='',
	@SQL_Table6_ID as nvarchar(299)				='',
	@SQL_Table7_ID as nvarchar(299)				='',
	@SQL_Table8_ID as nvarchar(299)				='',
	@SQL_Table9_ID as nvarchar(299)				='',
	@SQL_Table10_ID as nvarchar(299)			='',
	@SQL_Table11_ID as nvarchar(299)			='',
	@SQL_Table12_ID as nvarchar(299)			='',
	@SQL_Table13_ID as nvarchar(299)			='',
	@SQL_Table14_ID as nvarchar(299)			='',
	@SQL_Table15_ID as nvarchar(299)			='',

	@SQL_Use_Table2_ID as int						=0,
	@SQL_Use_Table3_ID as int						=0,
	@SQL_Use_Table4_ID as int						=0,
	@SQL_Use_Table5_ID as int						=0,
	@SQL_Use_Table6_ID as int						=0,
	@SQL_Use_Table7_ID as int						=0,
	@SQL_Use_Table8_ID as int						=0,
	@SQL_Use_Table9_ID as int						=0,
	@SQL_Use_Table10_ID as int						=0,
	@SQL_Use_Table11_ID as int						=0,
	@SQL_Use_Table12_ID as int						=0,
	@SQL_Use_Table13_ID as int						=0,
	@SQL_Use_Table14_ID as int						=0,
	@SQL_Use_Table15_ID as int						=0,

	@SQL_Table1_Connect_ID2 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID3 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID4 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID5 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID6 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID7 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID8 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID9 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID10 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID11 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID12 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID13 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID14 as nvarchar(299)	='',
	@SQL_Table1_Connect_ID15 as nvarchar(299)	='',

	@SQL_Table1_SourceDB as nvarchar(299)		='',
	@SQL_Table1_SourceSchema as nvarchar(299)	='',
	@SQL_Table1_SourceName as nvarchar(299)		='',
	@SQL_Table1_SourceRowID as nvarchar(299)	='|x|RowID',
	@SQL_Table1_SourceWhere as nvarchar(2000)	='',
	@SQL_Table1_SourceFields as nvarchar(1000)	='',
	@SQL_Table1_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table1_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',
	@SQL_Table1_SourceJoin as nvarchar(max)		='',

	@SQL_Table2_SourceDB as nvarchar(299)		='',
	@SQL_Table2_SourceSchema as nvarchar(299)	='',
	@SQL_Table2_SourceName as nvarchar(299)		='',
	@SQL_Table2_Connect_ID as nvarchar(299)		='',
	@SQL_Table2_SourceRowID as nvarchar(299)	='RowID',
	@SQL_Table2_SourceWhere as nvarchar(2000)	='',
	@SQL_Table2_SourceFields as nvarchar(1000)	='',
	@SQL_Table2_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table2_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table2_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table3_SourceDB as nvarchar(299)		='',
	@SQL_Table3_SourceSchema as nvarchar(299)	='',
	@SQL_Table3_SourceName as nvarchar(299)		='',
	@SQL_Table3_Connect_ID as nvarchar(299)		='',
	@SQL_Table3_SourceRowID as nvarchar(299)	='RowID',
	@SQL_Table3_SourceWhere as nvarchar(2000)	='',
	@SQL_Table3_SourceFields as nvarchar(1000)	='',
	@SQL_Table3_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table3_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table3_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table4_SourceDB as nvarchar(299)		='',
	@SQL_Table4_SourceSchema as nvarchar(299)	='',
	@SQL_Table4_SourceName as nvarchar(299)		='',
	@SQL_Table4_Connect_ID as nvarchar(299)		='',
	@SQL_Table4_SourceRowID as nvarchar(299)	='RowID',
	@SQL_Table4_SourceWhere as nvarchar(2000)	='',
	@SQL_Table4_SourceFields as nvarchar(1000)	='',
	@SQL_Table4_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table4_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table4_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table5_SourceDB as nvarchar(299)		='',
	@SQL_Table5_SourceSchema as nvarchar(299)	='',
	@SQL_Table5_SourceName as nvarchar(299)		='',
	@SQL_Table5_Connect_ID as nvarchar(299)		='',
	@SQL_Table5_SourceRowID as nvarchar(299)	='RowID',
	@SQL_Table5_SourceWhere as nvarchar(2000)	='',
	@SQL_Table5_SourceFields as nvarchar(1000)	='',
	@SQL_Table5_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table5_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table5_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table6_SourceDB as nvarchar(299)		='',
	@SQL_Table6_SourceSchema as nvarchar(299)	='',
	@SQL_Table6_SourceName as nvarchar(299)		='',
	@SQL_Table6_Connect_ID as nvarchar(299)		='',
	@SQL_Table6_SourceRowID as nvarchar(299)	='RowID',
	@SQL_Table6_SourceWhere as nvarchar(2000)	='',
	@SQL_Table6_SourceFields as nvarchar(1000)	='',
	@SQL_Table6_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table6_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table6_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table7_SourceDB as nvarchar(299)		='',
	@SQL_Table7_SourceSchema as nvarchar(299)	='',
	@SQL_Table7_SourceName as nvarchar(299)		='',
	@SQL_Table7_Connect_ID as nvarchar(299)		='',
	@SQL_Table7_SourceRowID as nvarchar(299)	='RowID',
	@SQL_Table7_SourceWhere as nvarchar(2000)	='',
	@SQL_Table7_SourceFields as nvarchar(1000)	='',
	@SQL_Table7_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table7_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table7_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table8_SourceDB as nvarchar(299)		='',
	@SQL_Table8_SourceSchema as nvarchar(299)	='',
	@SQL_Table8_SourceName as nvarchar(299)		='',
	@SQL_Table8_Connect_ID as nvarchar(299)		='',
	@SQL_Table8_SourceRowID as nvarchar(299)	='RowID',
	@SQL_Table8_SourceWhere as nvarchar(2000)	='',
	@SQL_Table8_SourceFields as nvarchar(1000)	='',
	@SQL_Table8_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table8_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table8_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table9_SourceDB as nvarchar(299)		='',
	@SQL_Table9_SourceSchema as nvarchar(299)	='',
	@SQL_Table9_SourceName as nvarchar(299)		='',
	@SQL_Table9_Connect_ID as nvarchar(299)		='',
	@SQL_Table9_SourceRowID as nvarchar(299)	='RowID',
	@SQL_Table9_SourceWhere as nvarchar(2000)	='',
	@SQL_Table9_SourceFields as nvarchar(1000)	='',
	@SQL_Table9_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table9_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table9_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table10_SourceDB as nvarchar(299)		='',
	@SQL_Table10_SourceSchema as nvarchar(299)	='',
	@SQL_Table10_SourceName as nvarchar(299)	='',
	@SQL_Table10_Connect_ID as nvarchar(299)	='',
	@SQL_Table10_SourceRowID as nvarchar(299) ='RowID',
	@SQL_Table10_SourceWhere as nvarchar(2000)	='',
	@SQL_Table10_SourceFields as nvarchar(1000)	='',
	@SQL_Table10_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table10_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table10_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table11_SourceDB as nvarchar(299)		='',
	@SQL_Table11_SourceSchema as nvarchar(299)	='',
	@SQL_Table11_SourceName as nvarchar(299)	='',
	@SQL_Table11_Connect_ID as nvarchar(299)	='',
	@SQL_Table11_SourceRowID as nvarchar(299) ='RowID',
	@SQL_Table11_SourceWhere as nvarchar(2000)	='',
	@SQL_Table11_SourceFields as nvarchar(1000)	='',
	@SQL_Table11_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table11_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table11_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table12_SourceDB as nvarchar(299)		='',
	@SQL_Table12_SourceSchema as nvarchar(299)	='',
	@SQL_Table12_SourceName as nvarchar(299)	='',
	@SQL_Table12_Connect_ID as nvarchar(299)	='',
	@SQL_Table12_SourceRowID as nvarchar(299) ='RowID',
	@SQL_Table12_SourceWhere as nvarchar(2000)	='',
	@SQL_Table12_SourceFields as nvarchar(1000)	='',
	@SQL_Table12_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table12_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table12_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table13_SourceDB as nvarchar(299)		='',
	@SQL_Table13_SourceSchema as nvarchar(299)	='',
	@SQL_Table13_SourceName as nvarchar(299)	='',
	@SQL_Table13_Connect_ID as nvarchar(299)	='',
	@SQL_Table13_SourceRowID as nvarchar(299)	='RowID',
	@SQL_Table13_SourceWhere as nvarchar(2000)	='',
	@SQL_Table13_SourceFields as nvarchar(1000)	='',
	@SQL_Table13_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table13_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table13_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table14_SourceDB as nvarchar(299)		='',
	@SQL_Table14_SourceSchema as nvarchar(299)	='',
	@SQL_Table14_SourceName as nvarchar(299)	='',
	@SQL_Table14_Connect_ID as nvarchar(299)	='',
	@SQL_Table14_SourceRowID as nvarchar(299)	='RowID',
	@SQL_Table14_SourceWhere as nvarchar(2000)	='',
	@SQL_Table14_SourceFields as nvarchar(1000)	='',
	@SQL_Table14_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table14_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table14_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_Table15_SourceDB as nvarchar(299)		='',
	@SQL_Table15_SourceSchema as nvarchar(299)	='',
	@SQL_Table15_SourceName as nvarchar(299)	='',
	@SQL_Table15_Connect_ID as nvarchar(299)	='',
	@SQL_Table15_SourceRowID as nvarchar(299) ='RowID',
	@SQL_Table15_SourceWhere as nvarchar(2000)	='',
	@SQL_Table15_SourceFields as nvarchar(1000)	='',
	@SQL_Table15_SourceJoinTyp as nvarchar(299)	='LEFT',
	@SQL_Table15_SourceValidFrom as nvarchar(299)='|x|Datensatz_gueltig_von',
	@SQL_Table15_SourceValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_TableTargetDB as nvarchar(299)			='Analysen',
	@SQL_TableTargetSchema as nvarchar(299)		='dbo',
	@SQL_TableTargetName as nvarchar(299)		='',
	@SQL_TableTargetID as nvarchar(299)			='SchluesselID',
	@SQL_TableTargetRowID1 as nvarchar(299)		='',
	@SQL_TableTargetRowID2 as nvarchar(299)		='',
	@SQL_TableTargetRowID3 as nvarchar(299)		='',
	@SQL_TableTargetRowID4 as nvarchar(299)		='',
	@SQL_TableTargetRowID5 as nvarchar(299)		='',
	@SQL_TableTargetRowID6 as nvarchar(299)		='',
	@SQL_TableTargetRowID7 as nvarchar(299)		='',
	@SQL_TableTargetRowID8 as nvarchar(299)		='',
	@SQL_TableTargetRowID9 as nvarchar(299)		='',
	@SQL_TableTargetRowID10 as nvarchar(299)	='',
	@SQL_TableTargetRowID11 as nvarchar(299)	='',
	@SQL_TableTargetRowID12 as nvarchar(299)	='',
	@SQL_TableTargetRowID13 as nvarchar(299)	='',
	@SQL_TableTargetRowID14 as nvarchar(299)	='',
	@SQL_TableTargetRowID15 as nvarchar(299)	='',
	@SQL_TableTargetRowIDNEW as nvarchar(299)	='RowID',

	@SQL_TableTargetDefinition1  as nvarchar(max)='',
	@SQL_TableTargetDefinition2  as nvarchar(max)='',
	@SQL_TableTargetDefinition3  as nvarchar(max)='',
	@SQL_TableTargetWhere		 as nvarchar(max)='',
	@SQL_TableTargetJoin		 as nvarchar(max)='',

	@SQL_TableTargetValidFrom as nvarchar(299)	='|x|Datensatz_gueltig_von',
	@SQL_TableTargetValidTo as nvarchar(299)	='|x|Datensatz_gueltig_bis',

	@SQL_TableLoggingName		as nvarchar(299)='Admin_Log',
	@SQL_TableLoggingString		as nvarchar(299)='',
	@SQL_TableTabStatusName		as nvarchar(299)='Admin_TabStatus',
	@SQL_TableTabStatusString	as nvarchar(299)='',
	@SQL_TableQlikLoadName		as nvarchar(299)='Admin_QlikLoad',
	@SQL_TableQlikLoadString	as nvarchar(299)='',
	@SQL_TableRelationTreeName	as nvarchar(299)='Admin_TabTree',
	@SQL_TableRelationTreeString as nvarchar(299)=''
as
Begin 

	PRINT 'Starte Skripabarbeitung für die Prozedur TabJoin'

	DECLARE @SQL_Table1_SourceString as nvarchar(500)
	DECLARE @SQL_Table2_SourceString as nvarchar(500)
	DECLARE @SQL_Table3_SourceString as nvarchar(500)
	DECLARE @SQL_Table4_SourceString as nvarchar(500)
	DECLARE @SQL_Table5_SourceString as nvarchar(500)
	DECLARE @SQL_Table6_SourceString as nvarchar(500)
	DECLARE @SQL_Table7_SourceString as nvarchar(500)
	DECLARE @SQL_Table8_SourceString as nvarchar(500)
	DECLARE @SQL_Table9_SourceString as nvarchar(500)
	DECLARE @SQL_Table10_SourceString as nvarchar(500)
	DECLARE @SQL_Table11_SourceString as nvarchar(500)
	DECLARE @SQL_Table12_SourceString as nvarchar(500)
	DECLARE @SQL_Table13_SourceString as nvarchar(500)
	DECLARE @SQL_Table14_SourceString as nvarchar(500)
	DECLARE @SQL_Table15_SourceString as nvarchar(500)
	DECLARE @SQL_TableTargetString	 as nvarchar(500)

	DECLARE @SQL as nvarchar(max)
	DECLARE @SQL1 as nvarchar(max)
	DECLARE @SQL2 as nvarchar(max)
	DECLARE @SQL3 as nvarchar(max)
	DECLARE @SQL4 as nvarchar(max)
	DECLARE @SQL5 as nvarchar(max)
	DECLARE @SQL6 as nvarchar(max)
	DECLARE @SQL7 as nvarchar(max)
	DECLARE @SQL8 as nvarchar(max)
	DECLARE @SQL9 as nvarchar(max)
	DECLARE @SQL10 as nvarchar(max)
	DECLARE @SQL_Konfig as nvarchar(max)
	DECLARE @SQL_Konfig1 as nvarchar(max)
	DECLARE @SQL_Konfig2 as nvarchar(max)
	DECLARE @SQL_Konfig3 as nvarchar(max)
	DECLARE @SQL_Konfig4 as nvarchar(max)
	DECLARE @SQL_Konfig5 as nvarchar(max)
	DECLARE @SQL_Konfig6 as nvarchar(max)
	DECLARE @SQL_Konfig7 as nvarchar(max)
	DECLARE @SQL_Konfig8 as nvarchar(max)
	DECLARE @SQL_Konfig9 as nvarchar(max)
	DECLARE @SQL_Konfig10 as nvarchar(max)
	
	DECLARE @Konfiguration as nvarchar(max)
	DECLARE @Table_Status_LastChangeOnDate as int

	DECLARE @LastLoad DateTime2
	DECLARE @LastUpdate as DateTime2
	DECLARE @LastFullLoad DateTime2
	DECLARE @TableLastUpdate DateTime2
	DECLARE @TableSourceLastUpdate1 as DateTime2
	DECLARE @TableSourceLastUpdate2 as DateTime2
	DECLARE @TableSourceLastUpdate3 as DateTime2
	DECLARE @TableSourceLastUpdate4 as DateTime2
	DECLARE @TableSourceLastUpdate5 as DateTime2
	DECLARE @TableSourceLastUpdate6 as DateTime2
	DECLARE @TableSourceLastUpdate7 as DateTime2
	DECLARE @TableSourceLastUpdate8 as DateTime2
	DECLARE @TableSourceLastUpdate9 as DateTime2
	DECLARE @TableSourceLastUpdate10 as DateTime2
	DECLARE @TableSourceLastUpdate11 as DateTime2
	DECLARE @TableSourceLastUpdate12 as DateTime2
	DECLARE @TableSourceLastUpdate13 as DateTime2
	DECLARE @TableSourceLastUpdate14 as DateTime2
	DECLARE @TableSourceLastUpdate15 as DateTime2
	
	DECLARE @Zeit DateTime2
	DECLARE @Start DateTime2
	DECLARE @Fehler as int
	DECLARE @FehlerText as nvarchar(500)
	DECLARE @Datenweg int
	DECLARE @Zaehler as int
	DECLARE @Praefix as nvarchar(100)
	DECLARE @Zeilenanzahl as bigint
	DECLARE @StepPraefix as nvarchar(100)
	DECLARE @RowCount as bigint
	DECLARE @StepText nvarchar(500)
	DECLARE @LogID bigint
	DECLARE @CountDate as Date
	DECLARE	@SQL_Connect as nvarchar(max)	
	DECLARE @SQL_ConnectID_Dim as nvarchar(200)
	DECLARE @SQL_ConnectID_Fak as nvarchar(200)
	DECLARE @SQL_ConnectTableID as nvarchar(200)
	DECLARE @SQL_ConnectSourceString as nvarchar(400)
	DECLARE @SQL_ConnectValidFrom as nvarchar(200)
	DECLARE @SQL_ConnectValidTo as nvarchar(200)
	DECLARE @SQL_SourceJoinTyp as nvarchar(200)
	DECLARE @Liste_TargetID as nvarchar(max)
	DECLARE @Liste_ConnectingFields as nvarchar(max)
	DECLARE @Liste_TableString as nvarchar(max)
	DECLARE @Liste_ColumnsInTableORG as nvarchar(max)
	DECLARE @Liste_ColumnsInTableTest as nvarchar(max)
	DECLARE @Liste_ColumnsInTableTarget as nvarchar(max)
	DECLARE @Liste_Index as nvarchar(10)
	DECLARE @SQL_TempTableString as nvarchar(400)
	DECLARE @Qlik_Ladeskript as nvarchar(max)
	DECLARE @Fieldlist6 as nvarchar(max)
	DECLARE @SQL_CaseWhenRowID as nvarchar(max)
	DECLARE @SQL_TableTargetRowID as nvarchar(200)
	DECLARE @SQL_TableSourceRowID as nvarchar(200)
	DECLARE @UseConnectTabelID	as int		=0		
	DECLARE @SQL_TableID as nvarchar(200)
	DECLARE @Schleifenende	as int		=0	
	
	
	DECLARE @Table1_Valid as int
	DECLARE @Table2_Valid as int
	DECLARE @Table3_Valid as int
	DECLARE @Table4_Valid as int
	DECLARE @Table5_Valid as int
	DECLARE @Table6_Valid as int
	DECLARE @Table7_Valid as int
	DECLARE @Table8_Valid as int
	DECLARE @Table9_Valid as int
	DECLARE @Table10_Valid as int
	DECLARE @table11_Valid as int
	DECLARE @table12_Valid as int
	DECLARE @table13_Valid as int
	DECLARE @table14_Valid as int
	DECLARE @table15_Valid as int

	DECLARE @SQL_SourceWhere as nvarchar(max)
	DECLARE @SQL_SourceRowID as nvarchar(max)
	DECLARE @SQL_Schluessel  as nvarchar(max)
	DECLARE @SQL_SourceFields  as nvarchar(max)

	DECLARE @Loop as int
	DECLARE @LoopIndex as int
	DECLARE @ValidLoop as int
	DECLARE @MaxDelayTimestamp as DateTime2
	DECLARE @SQL_TableSourceSYSDB as varchar(50)

	SET @SQL_TableSourceSYSDB='replicate'
	SET @SQL_Konfig=''; SET @SQL_Konfig1=''; SET @SQL_Konfig2=''; SET @SQL_Konfig3=''; SET @SQL_Konfig4=''; SET @SQL_Konfig5=''; SET @SQL_Konfig6=''; SET @SQL_Konfig7=''; SET @SQL_Konfig8=''; SET @SQL_Konfig9=''; SET @SQL_Konfig10=''

	Set @SQL_Konfig=concat('
		@TestLoop =''''',replace(@TestLoop,'''',''''''''''),''''', 
		@DeltaDays =',replace(@DeltaDays,'''',''''''''''),', 
		@FullloadYears =',replace(@FullloadYears,'''',''''''''''),', 
		@Ladeverfahren =''''',replace(@Ladeverfahren,'''',''''''''''),''''', 
		@TEMPPraefix =''''',replace(@TEMPPraefix,'''',''''''''''),''''',
		@DaysToFullLoad =',replace(@DaysToFullLoad,'''',''''''''''),', 
		@TEMPLoeschen =',replace(@TEMPLoeschen,'''',''''''''''),',
		@MaxDelay=',replace(@MaxDelay,'''',''''''''''),',
		@LastChangeOnDate =',replace(@LastChangeOnDate,'''',''''''''''),',

		@SQL_Table1_ID =''''',replace(@SQL_Table1_ID,'''',''''''''''),''''',
		@SQL_Table2_ID =''''',replace(@SQL_Table2_ID,'''',''''''''''),''''',
		@SQL_Table3_ID =''''',replace(@SQL_Table3_ID,'''',''''''''''),''''',
		@SQL_Table4_ID =''''',replace(@SQL_Table4_ID,'''',''''''''''),''''',
		@SQL_Table5_ID =''''',replace(@SQL_Table5_ID,'''',''''''''''),''''',
		@SQL_Table6_ID =''''',replace(@SQL_Table6_ID,'''',''''''''''),''''',
		@SQL_Table7_ID =''''',replace(@SQL_Table7_ID,'''',''''''''''),''''',
		@SQL_Table8_ID =''''',replace(@SQL_Table8_ID,'''',''''''''''),''''',
		@SQL_Table9_ID =''''',replace(@SQL_Table9_ID,'''',''''''''''),''''',
		@SQL_Table10_ID =''''',replace(@SQL_Table10_ID,'''',''''''''''),''''',
		@SQL_Table11_ID =''''',replace(@SQL_Table11_ID,'''',''''''''''),''''',
		@SQL_Table12_ID =''''',replace(@SQL_Table12_ID,'''',''''''''''),''''',
		@SQL_Table13_ID =''''',replace(@SQL_Table13_ID,'''',''''''''''),''''',
		@SQL_Table14_ID =''''',replace(@SQL_Table14_ID,'''',''''''''''),''''',
		@SQL_Table15_ID =''''',replace(@SQL_Table15_ID,'''',''''''''''),''''',

		@SQL_Use_Table2_ID =',replace(@SQL_Use_Table2_ID,'''',''''''''''),',
		@SQL_Use_Table3_ID =',replace(@SQL_Use_Table3_ID,'''',''''''''''),',
		@SQL_Use_Table4_ID =',replace(@SQL_Use_Table4_ID,'''',''''''''''),',
		@SQL_Use_Table5_ID =',replace(@SQL_Use_Table5_ID,'''',''''''''''),',
		@SQL_Use_Table6_ID =',replace(@SQL_Use_Table6_ID,'''',''''''''''),',
		@SQL_Use_Table7_ID =',replace(@SQL_Use_Table7_ID,'''',''''''''''),',
		@SQL_Use_Table8_ID =',replace(@SQL_Use_Table8_ID,'''',''''''''''),',
		@SQL_Use_Table9_ID =',replace(@SQL_Use_Table9_ID,'''',''''''''''),',
		@SQL_Use_Table10_ID =',replace(@SQL_Use_Table10_ID,'''',''''''''''),',
		@SQL_Use_Table11_ID =',replace(@SQL_Use_Table11_ID,'''',''''''''''),',
		@SQL_Use_Table12_ID =',replace(@SQL_Use_Table12_ID,'''',''''''''''),',
		@SQL_Use_Table13_ID =',replace(@SQL_Use_Table13_ID,'''',''''''''''),',
		@SQL_Use_Table14_ID =',replace(@SQL_Use_Table14_ID,'''',''''''''''),',
		@SQL_Use_Table15_ID =',replace(@SQL_Use_Table15_ID,'''',''''''''''),',
		')
	Set @SQL_Konfig1=concat('
		@SQL_Table1_Connect_ID2 =''''',replace(@SQL_Table1_Connect_ID2,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID3 =''''',replace(@SQL_Table1_Connect_ID3,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID4 =''''',replace(@SQL_Table1_Connect_ID4,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID5 =''''',replace(@SQL_Table1_Connect_ID5,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID6 =''''',replace(@SQL_Table1_Connect_ID6,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID7 =''''',replace(@SQL_Table1_Connect_ID7,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID8 =''''',replace(@SQL_Table1_Connect_ID8,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID9 =''''',replace(@SQL_Table1_Connect_ID9,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID10 =''''',replace(@SQL_Table1_Connect_ID10,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID11 =''''',replace(@SQL_Table1_Connect_ID11,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID12 =''''',replace(@SQL_Table1_Connect_ID12,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID13 =''''',replace(@SQL_Table1_Connect_ID13,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID14 =''''',replace(@SQL_Table1_Connect_ID14,'''',''''''''''),''''',
		@SQL_Table1_Connect_ID15 =''''',replace(@SQL_Table1_Connect_ID15,'''',''''''''''),''''',
	
		@SQL_Table1_SourceDB 					=''''',replace(@SQL_Table1_SourceDB,'''',''''''''''),''''',
		@SQL_Table1_SourceSchema 				=''''',replace(@SQL_Table1_SourceSchema,'''',''''''''''),''''',
		@SQL_Table1_SourceName 					=''''',replace(@SQL_Table1_SourceName,'''',''''''''''),''''',
		@SQL_Table1_SourceRowID 				=''''',replace(@SQL_Table1_SourceRowID,'''',''''''''''),''''',
		@SQL_Table1_SourceWhere 				=''''',replace(@SQL_Table1_SourceWhere,'''',''''''''''),''''',
		@SQL_Table1_SourceFields 				=''''',replace(@SQL_Table1_SourceFields,'''',''''''''''),''''',
		@SQL_Table1_SourceValidFrom 			=''''',replace(@SQL_Table1_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table1_SourceValidTo 				=''''',replace(@SQL_Table1_SourceValidTo,'''',''''''''''),''''',
		@SQL_Table1_SourceJoin 					=''''',replace(@SQL_Table1_SourceJoin,'''',''''''''''),''''',

		@SQL_Table2_SourceDB 					=''''',replace(@SQL_Table2_SourceDB,'''',''''''''''),''''',
		@SQL_Table2_SourceSchema 				=''''',replace(@SQL_Table2_SourceSchema,'''',''''''''''),''''',
		@SQL_Table2_SourceName 					=''''',replace(@SQL_Table2_SourceName,'''',''''''''''),''''',
		@SQL_Table2_Connect_ID 					=''''',replace(@SQL_Table2_Connect_ID,'''',''''''''''),''''',
		@SQL_Table2_SourceRowID 				=''''',replace(@SQL_Table2_SourceRowID,'''',''''''''''),''''',
		@SQL_Table2_SourceWhere 				=''''',replace(@SQL_Table2_SourceWhere,'''',''''''''''),''''',
		@SQL_Table2_SourceFields 				=''''',replace(@SQL_Table2_SourceFields,'''',''''''''''),''''',
		@SQL_Table2_SourceJoinTyp 				=''''',replace(@SQL_Table2_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table2_SourceValidFrom 			=''''',replace(@SQL_Table2_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table2_SourceValidTo 				=''''',replace(@SQL_Table2_SourceValidTo,'''',''''''''''),''''',
		')
	Set @SQL_Konfig2=concat('
		@SQL_Table3_SourceDB 					=''''',replace(@SQL_Table3_SourceDB,'''',''''''''''),''''',
		@SQL_Table3_SourceSchema 				=''''',replace(@SQL_Table3_SourceSchema,'''',''''''''''),''''',
		@SQL_Table3_SourceName 					=''''',replace(@SQL_Table3_SourceName,'''',''''''''''),''''',
		@SQL_Table3_Connect_ID 					=''''',replace(@SQL_Table3_Connect_ID,'''',''''''''''),''''',
		@SQL_Table3_SourceRowID 				=''''',replace(@SQL_Table3_SourceRowID,'''',''''''''''),''''',
		@SQL_Table3_SourceWhere 				=''''',replace(@SQL_Table3_SourceWhere,'''',''''''''''),''''',
		@SQL_Table3_SourceFields 				=''''',replace(@SQL_Table3_SourceFields,'''',''''''''''),''''',
		@SQL_Table3_SourceJoinTyp 				=''''',replace(@SQL_Table3_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table3_SourceValidFrom 			=''''',replace(@SQL_Table3_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table3_SourceValidTo 				=''''',replace(@SQL_Table3_SourceValidTo,'''',''''''''''),''''',

		@SQL_Table4_SourceDB 					=''''',replace(@SQL_Table4_SourceDB,'''',''''''''''),''''',
		@SQL_Table4_SourceSchema 				=''''',replace(@SQL_Table4_SourceSchema,'''',''''''''''),''''',
		@SQL_Table4_SourceName 					=''''',replace(@SQL_Table4_SourceName,'''',''''''''''),''''',
		@SQL_Table4_Connect_ID 					=''''',replace(@SQL_Table4_Connect_ID,'''',''''''''''),''''',
		@SQL_Table4_SourceRowID 				=''''',replace(@SQL_Table4_SourceRowID,'''',''''''''''),''''',
		@SQL_Table4_SourceWhere 				=''''',replace(@SQL_Table4_SourceWhere,'''',''''''''''),''''',
		@SQL_Table4_SourceFields 				=''''',replace(@SQL_Table4_SourceFields,'''',''''''''''),''''',
		@SQL_Table4_SourceJoinTyp 				=''''',replace(@SQL_Table4_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table4_SourceValidFrom 			=''''',replace(@SQL_Table4_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table4_SourceValidTo 				=''''',replace(@SQL_Table4_SourceValidTo,'''',''''''''''),''''',

		@SQL_Table5_SourceDB 					=''''',replace(@SQL_Table5_SourceDB,'''',''''''''''),''''',
		@SQL_Table5_SourceSchema 				=''''',replace(@SQL_Table5_SourceSchema,'''',''''''''''),''''',
		@SQL_Table5_SourceName 					=''''',replace(@SQL_Table5_SourceName,'''',''''''''''),''''',
		@SQL_Table5_Connect_ID 					=''''',replace(@SQL_Table5_Connect_ID,'''',''''''''''),''''',
		@SQL_Table5_SourceRowID 				=''''',replace(@SQL_Table5_SourceRowID,'''',''''''''''),''''',
		@SQL_Table5_SourceWhere 				=''''',replace(@SQL_Table5_SourceWhere,'''',''''''''''),''''',
		@SQL_Table5_SourceFields 				=''''',replace(@SQL_Table5_SourceFields,'''',''''''''''),''''',
		@SQL_Table5_SourceJoinTyp 				=''''',replace(@SQL_Table5_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table5_SourceValidFrom 			=''''',replace(@SQL_Table5_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table5_SourceValidTo 				=''''',replace(@SQL_Table5_SourceValidTo,'''',''''''''''),''''',

		@SQL_Table6_SourceDB 					=''''',replace(@SQL_Table6_SourceDB,'''',''''''''''),''''',
		@SQL_Table6_SourceSchema 				=''''',replace(@SQL_Table6_SourceSchema,'''',''''''''''),''''',
		@SQL_Table6_SourceName 					=''''',replace(@SQL_Table6_SourceName,'''',''''''''''),''''',
		@SQL_Table6_Connect_ID 					=''''',replace(@SQL_Table6_Connect_ID,'''',''''''''''),''''',
		@SQL_Table6_SourceRowID 				=''''',replace(@SQL_Table6_SourceRowID,'''',''''''''''),''''',
		@SQL_Table6_SourceWhere 				=''''',replace(@SQL_Table6_SourceWhere,'''',''''''''''),''''',
		@SQL_Table6_SourceFields 				=''''',replace(@SQL_Table6_SourceFields,'''',''''''''''),''''',
		@SQL_Table6_SourceJoinTyp 				=''''',replace(@SQL_Table6_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table6_SourceValidFrom 			=''''',replace(@SQL_Table6_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table6_SourceValidTo 				=''''',replace(@SQL_Table6_SourceValidTo,'''',''''''''''),''''',
		')
	Set @SQL_Konfig3=concat('
		@SQL_Table7_SourceDB 					=''''',replace(@SQL_Table7_SourceDB,'''',''''''''''),''''',
		@SQL_Table7_SourceSchema 				=''''',replace(@SQL_Table7_SourceSchema,'''',''''''''''),''''',
		@SQL_Table7_SourceName 					=''''',replace(@SQL_Table7_SourceName,'''',''''''''''),''''',
		@SQL_Table7_Connect_ID 					=''''',replace(@SQL_Table7_Connect_ID,'''',''''''''''),''''',
		@SQL_Table7_SourceRowID 				=''''',replace(@SQL_Table7_SourceRowID,'''',''''''''''),''''',
		@SQL_Table7_SourceWhere 				=''''',replace(@SQL_Table7_SourceWhere,'''',''''''''''),''''',
		@SQL_Table7_SourceFields 				=''''',replace(@SQL_Table7_SourceFields,'''',''''''''''),''''',
		@SQL_Table7_SourceJoinTyp 				=''''',replace(@SQL_Table7_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table7_SourceValidFrom 			=''''',replace(@SQL_Table7_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table7_SourceValidTo 				=''''',replace(@SQL_Table7_SourceValidTo,'''',''''''''''),''''',

		@SQL_Table8_SourceDB 					=''''',replace(@SQL_Table8_SourceDB,'''',''''''''''),''''',
		@SQL_Table8_SourceSchema 				=''''',replace(@SQL_Table8_SourceSchema,'''',''''''''''),''''',
		@SQL_Table8_SourceName 					=''''',replace(@SQL_Table8_SourceName,'''',''''''''''),''''',
		@SQL_Table8_Connect_ID 					=''''',replace(@SQL_Table8_Connect_ID,'''',''''''''''),''''',
		@SQL_Table8_SourceRowID 				=''''',replace(@SQL_Table8_SourceRowID,'''',''''''''''),''''',
		@SQL_Table8_SourceWhere 				=''''',replace(@SQL_Table8_SourceWhere,'''',''''''''''),''''',
		@SQL_Table8_SourceFields 				=''''',replace(@SQL_Table8_SourceFields,'''',''''''''''),''''',
		@SQL_Table8_SourceJoinTyp 				=''''',replace(@SQL_Table8_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table8_SourceValidFrom 			=''''',replace(@SQL_Table8_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table8_SourceValidTo 				=''''',replace(@SQL_Table8_SourceValidTo,'''',''''''''''),''''',
	
		@SQL_Table9_SourceDB 					=''''',replace(@SQL_Table9_SourceDB,'''',''''''''''),''''',
		@SQL_Table9_SourceSchema 				=''''',replace(@SQL_Table9_SourceSchema,'''',''''''''''),''''',
		@SQL_Table9_SourceName 					=''''',replace(@SQL_Table9_SourceName,'''',''''''''''),''''',
		@SQL_Table9_Connect_ID 					=''''',replace(@SQL_Table9_Connect_ID,'''',''''''''''),''''',
		@SQL_Table9_SourceRowID 				=''''',replace(@SQL_Table9_SourceRowID,'''',''''''''''),''''',
		@SQL_Table9_SourceWhere 				=''''',replace(@SQL_Table9_SourceWhere,'''',''''''''''),''''',
		@SQL_Table9_SourceFields 				=''''',replace(@SQL_Table9_SourceFields,'''',''''''''''),''''',
		@SQL_Table9_SourceJoinTyp 				=''''',replace(@SQL_Table9_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table9_SourceValidFrom 			=''''',replace(@SQL_Table9_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table9_SourceValidTo 				=''''',replace(@SQL_Table9_SourceValidTo,'''',''''''''''),''''',

		@SQL_Table10_SourceDB 					=''''',replace(@SQL_Table10_SourceDB,'''',''''''''''),''''',
		@SQL_Table10_SourceSchema 				=''''',replace(@SQL_Table10_SourceSchema,'''',''''''''''),''''',
		@SQL_Table10_SourceName 				=''''',replace(@SQL_Table10_SourceName,'''',''''''''''),''''',
		@SQL_Table10_Connect_ID 				=''''',replace(@SQL_Table10_Connect_ID,'''',''''''''''),''''',
		@SQL_Table10_SourceRowID 				=''''',replace(@SQL_Table10_SourceRowID,'''',''''''''''),''''',
		@SQL_Table10_SourceWhere 				=''''',replace(@SQL_Table10_SourceWhere,'''',''''''''''),''''',
		@SQL_Table10_SourceFields 				=''''',replace(@SQL_Table10_SourceFields,'''',''''''''''),''''',
		@SQL_Table10_SourceJoinTyp 				=''''',replace(@SQL_Table10_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table10_SourceValidFrom 			=''''',replace(@SQL_Table10_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table10_SourceValidTo 				=''''',replace(@SQL_Table10_SourceValidTo,'''',''''''''''),''''',
		')
	Set @SQL_Konfig4=concat('
		@SQL_Table11_SourceDB 					=''''',replace(@SQL_Table11_SourceDB,'''',''''''''''),''''',
		@SQL_Table11_SourceSchema 				=''''',replace(@SQL_Table11_SourceSchema,'''',''''''''''),''''',
		@SQL_Table11_SourceName 				=''''',replace(@SQL_Table11_SourceName,'''',''''''''''),''''',
		@SQL_Table11_Connect_ID 				=''''',replace(@SQL_Table11_Connect_ID,'''',''''''''''),''''',
		@SQL_Table11_SourceRowID 				=''''',replace(@SQL_Table11_SourceRowID,'''',''''''''''),''''',
		@SQL_Table11_SourceWhere 				=''''',replace(@SQL_Table11_SourceWhere,'''',''''''''''),''''',
		@SQL_Table11_SourceFields 				=''''',replace(@SQL_Table11_SourceFields,'''',''''''''''),''''',
		@SQL_Table11_SourceJoinTyp 				=''''',replace(@SQL_Table11_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table11_SourceValidFrom 			=''''',replace(@SQL_Table11_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table11_SourceValidTo 				=''''',replace(@SQL_Table11_SourceValidTo,'''',''''''''''),''''',

		@SQL_Table12_SourceDB 					=''''',replace(@SQL_Table12_SourceDB,'''',''''''''''),''''',
		@SQL_Table12_SourceSchema 				=''''',replace(@SQL_Table12_SourceSchema,'''',''''''''''),''''',
		@SQL_Table12_SourceName 				=''''',replace(@SQL_Table12_SourceName,'''',''''''''''),''''',
		@SQL_Table12_Connect_ID 				=''''',replace(@SQL_Table12_Connect_ID,'''',''''''''''),''''',
		@SQL_Table12_SourceRowID 				=''''',replace(@SQL_Table12_SourceRowID,'''',''''''''''),''''',
		@SQL_Table12_SourceWhere 				=''''',replace(@SQL_Table12_SourceWhere,'''',''''''''''),''''',
		@SQL_Table12_SourceFields 				=''''',replace(@SQL_Table12_SourceFields,'''',''''''''''),''''',
		@SQL_Table12_SourceJoinTyp 				=''''',replace(@SQL_Table12_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table12_SourceValidFrom 			=''''',replace(@SQL_Table12_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table12_SourceValidTo 				=''''',replace(@SQL_Table12_SourceValidTo,'''',''''''''''),''''',
		')
	Set @SQL_Konfig5=concat('
		@SQL_Table13_SourceDB 					=''''',replace(@SQL_Table13_SourceDB,'''',''''''''''),''''',
		@SQL_Table13_SourceSchema 				=''''',replace(@SQL_Table13_SourceSchema,'''',''''''''''),''''',
		@SQL_Table13_SourceName 				=''''',replace(@SQL_Table13_SourceName,'''',''''''''''),''''',
		@SQL_Table13_Connect_ID 				=''''',replace(@SQL_Table13_Connect_ID,'''',''''''''''),''''',
		@SQL_Table13_SourceRowID 				=''''',replace(@SQL_Table13_SourceRowID,'''',''''''''''),''''',
		@SQL_Table13_SourceWhere 				=''''',replace(@SQL_Table13_SourceWhere,'''',''''''''''),''''',
		@SQL_Table13_SourceFields 				=''''',replace(@SQL_Table13_SourceFields,'''',''''''''''),''''',
		@SQL_Table13_SourceJoinTyp 				=''''',replace(@SQL_Table13_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table13_SourceValidFrom 			=''''',replace(@SQL_Table13_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table13_SourceValidTo 				=''''',replace(@SQL_Table13_SourceValidTo,'''',''''''''''),''''',

		@SQL_Table14_SourceDB 					=''''',replace(@SQL_Table14_SourceDB,'''',''''''''''),''''',
		@SQL_Table14_SourceSchema 				=''''',replace(@SQL_Table14_SourceSchema,'''',''''''''''),''''',
		@SQL_Table14_SourceName 				=''''',replace(@SQL_Table14_SourceName,'''',''''''''''),''''',
		@SQL_Table14_Connect_ID 				=''''',replace(@SQL_Table14_Connect_ID,'''',''''''''''),''''',
		@SQL_Table14_SourceRowID 				=''''',replace(@SQL_Table14_SourceRowID,'''',''''''''''),''''',
		@SQL_Table14_SourceWhere 				=''''',replace(@SQL_Table14_SourceWhere,'''',''''''''''),''''',
		@SQL_Table14_SourceFields 				=''''',replace(@SQL_Table14_SourceFields,'''',''''''''''),''''',
		@SQL_Table14_SourceJoinTyp 				=''''',replace(@SQL_Table14_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table14_SourceValidFrom 			=''''',replace(@SQL_Table14_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table14_SourceValidTo 				=''''',replace(@SQL_Table14_SourceValidTo,'''',''''''''''),''''',

		@SQL_Table15_SourceDB 					=''''',replace(@SQL_Table15_SourceDB,'''',''''''''''),''''',
		@SQL_Table15_SourceSchema 				=''''',replace(@SQL_Table15_SourceSchema,'''',''''''''''),''''',
		@SQL_Table15_SourceName 				=''''',replace(@SQL_Table15_SourceName,'''',''''''''''),''''',
		@SQL_Table15_Connect_ID 				=''''',replace(@SQL_Table15_Connect_ID,'''',''''''''''),''''',
		@SQL_Table15_SourceRowID 				=''''',replace(@SQL_Table15_SourceRowID,'''',''''''''''),''''',
		@SQL_Table15_SourceWhere 				=''''',replace(@SQL_Table15_SourceWhere,'''',''''''''''),''''',
		@SQL_Table15_SourceFields 				=''''',replace(@SQL_Table15_SourceFields,'''',''''''''''),''''',
		@SQL_Table15_SourceJoinTyp 				=''''',replace(@SQL_Table15_SourceJoinTyp,'''',''''''''''),''''',
		@SQL_Table15_SourceValidFrom 			=''''',replace(@SQL_Table15_SourceValidFrom,'''',''''''''''),''''',
		@SQL_Table15_SourceValidTo 				=''''',replace(@SQL_Table15_SourceValidTo,'''',''''''''''),''''',
		')
	Set @SQL_Konfig6=concat('
		@SQL_TableTargetDB 					=''''',replace(@SQL_TableTargetDB,'''',''''''''''),''''',
		@SQL_TableTargetSchema 				=''''',replace(@SQL_TableTargetSchema,'''',''''''''''),''''',
		@SQL_TableTargetName 				=''''',replace(@SQL_TableTargetName,'''',''''''''''),''''',
		@SQL_TableTargetID 					=''''',replace(@SQL_TableTargetID,'''',''''''''''),''''',
		@SQL_TableTargetRowID1 				=''''',replace(@SQL_TableTargetRowID1,'''',''''''''''),''''',
		@SQL_TableTargetRowID2 				=''''',replace(@SQL_TableTargetRowID2,'''',''''''''''),''''',
		@SQL_TableTargetRowID3 				=''''',replace(@SQL_TableTargetRowID3,'''',''''''''''),''''',
		@SQL_TableTargetRowID4 				=''''',replace(@SQL_TableTargetRowID4,'''',''''''''''),''''',
		@SQL_TableTargetRowID5 				=''''',replace(@SQL_TableTargetRowID5,'''',''''''''''),''''',
		@SQL_TableTargetRowID6 				=''''',replace(@SQL_TableTargetRowID6,'''',''''''''''),''''',
		@SQL_TableTargetRowID7 				=''''',replace(@SQL_TableTargetRowID7,'''',''''''''''),''''',
		@SQL_TableTargetRowID8 				=''''',replace(@SQL_TableTargetRowID8,'''',''''''''''),''''',
		@SQL_TableTargetRowID9 				=''''',replace(@SQL_TableTargetRowID9,'''',''''''''''),''''',
		@SQL_TableTargetRowID10 			=''''',replace(@SQL_TableTargetRowID10,'''',''''''''''),''''',
		@SQL_TableTargetRowID11 			=''''',replace(@SQL_TableTargetRowID11,'''',''''''''''),''''',
		@SQL_TableTargetRowID12 			=''''',replace(@SQL_TableTargetRowID12,'''',''''''''''),''''',
		@SQL_TableTargetRowID13 			=''''',replace(@SQL_TableTargetRowID13,'''',''''''''''),''''',
		@SQL_TableTargetRowID14 			=''''',replace(@SQL_TableTargetRowID14,'''',''''''''''),''''',
		@SQL_TableTargetRowID15 			=''''',replace(@SQL_TableTargetRowID15,'''',''''''''''),''''',
		@SQL_TableTargetRowIDNEW 			=''''',replace(@SQL_TableTargetRowIDNEW,'''',''''''''''),''''',
		')
	Set @SQL_Konfig7=concat('
		@SQL_TableTargetDefinition1  =''''',replace(@SQL_TableTargetDefinition1,'''',''''''''''),''''',
		')
	Set @SQL_Konfig8=concat('	
		@SQL_TableTargetDefinition2  =''''',replace(@SQL_TableTargetDefinition2,'''',''''''''''),''''',
		')
	Set @SQL_Konfig9=concat('
		@SQL_TableTargetDefinition3  =''''',replace(@SQL_TableTargetDefinition3,'''',''''''''''),''''',
		')
	Set @SQL_Konfig10=concat('
		@SQL_TableTargetWhere		 =''''',replace(@SQL_TableTargetWhere,'''',''''''''''),''''',
		@SQL_TableTargetJoin		 =''''',replace(@SQL_TableTargetJoin,'''',''''''''''),''''',

		@SQL_TableTargetValidFrom =''''',replace(@SQL_TableTargetValidFrom,'''',''''''''''),''''',
		@SQL_TableTargetValidTo =''''',replace(@SQL_TableTargetValidTo,'''',''''''''''),''''',

		@SQL_TableLoggingName		=''''',replace(@SQL_TableLoggingName,'''',''''''''''),''''',
		@SQL_TableLoggingString		=''''',replace(@SQL_TableLoggingString,'''',''''''''''),''''',
		@SQL_TableTabStatusName		=''''',replace(@SQL_TableTabStatusName,'''',''''''''''),''''',
		@SQL_TableTabStatusString	=''''',replace(@SQL_TableTabStatusString,'''',''''''''''),''''',
		@SQL_TableQlikLoadName		=''''',replace(@SQL_TableQlikLoadName,'''',''''''''''),''''',
		@SQL_TableQlikLoadString	=''''',replace(@SQL_TableQlikLoadString,'''',''''''''''),''''',
		@SQL_TableRelationTreeName	=''''',replace(@SQL_TableRelationTreeName,'''',''''''''''),''''',
		@SQL_TableRelationTreeString =''''',replace(@SQL_TableRelationTreeString,'''',''''''''''),'''''
		')

	SET @Start=Getdate();
	SET @Loop = 1;

	If @MaxDelay<1
		SET @MaxDelayTimestamp=cast(Dateadd(DAY,@MaxDelay,cast(getdate() as date)) as DateTime2)
	else
		SET @MaxDelayTimestamp=Dateadd(MINUTE,-@MaxDelay,getdate())

	If LEN(Trim(@SQL_TableLoggingString))=0 or @SQL_TableLoggingString is null
		SET @SQL_TableLoggingString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableLoggingName)

	If LEN(Trim(@SQL_TableTabStatusString))=0 or @SQL_TableTabStatusString is null
		SET @SQL_TableTabStatusString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableTabStatusName)

	If LEN(Trim(@SQL_TableQlikLoadString))=0 or @SQL_TableQlikLoadString is null
		SET @SQL_TableQlikLoadString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableQlikLoadName)
		
	If LEN(Trim(@SQL_TableRelationTreeString))=0 or @SQL_TableRelationTreeString is null
		SET @SQL_TableRelationTreeString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableRelationTreeName)

	if (len(trim(@SQL_TableTargetDB))=0 or @SQL_TableTargetDB is null) and @SQL_Table1_SourceDB is not null and LEN(trim(@SQL_Table1_SourceDB))>0
		Set @SQL_TableTargetDB=@SQL_Table1_SourceDB
	if (len(trim(@SQL_TableTargetSchema))=0 or @SQL_TableTargetSchema is null) and @SQL_Table1_SourceSchema is not null and LEN(trim(@SQL_Table1_SourceSchema))>0
		Set @SQL_TableTargetSchema=@SQL_Table1_SourceSchema	

	if (len(trim(@SQL_Table1_SourceDB))=0 or @SQL_Table1_SourceDB is null) and @SQL_TableTargetDB is not null and LEN(trim(@SQL_TableTargetDB))>0
		Set @SQL_Table1_SourceDB=@SQL_TableTargetDB
	if (len(trim(@SQL_Table1_SourceSchema))=0 or @SQL_Table1_SourceSchema is null) and @SQL_TableTargetSchema is not null and LEN(trim(@SQL_TableTargetSchema))>0
		Set @SQL_Table1_SourceSchema=@SQL_TableTargetSchema	
	if CHARINDEX('|x|',@SQL_Table1_SourceRowID)=0
		Set @SQL_Table1_SourceRowID=Concat('|x|',@SQL_Table1_SourceRowID)

	if len(trim(@SQL_Table2_SourceName))>0 and len(trim(@SQL_Table2_SourceDB))=0 or @SQL_Table2_SourceDB is null
		Set @SQL_Table2_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table2_SourceName))>0 and len(trim(@SQL_Table2_SourceSchema))=0 or @SQL_Table2_SourceSchema is null
		Set @SQL_Table2_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table2_SourceName))>0 and len(trim(@SQL_Table2_Connect_ID))=0 or @SQL_Table2_Connect_ID is null
		Set @SQL_Table2_Connect_ID=@SQL_Table1_Connect_ID2
	if len(trim(@SQL_Table2_SourceName))>0 and len(trim(@SQL_Table2_SourceRowID))=0 or @SQL_Table2_SourceRowID is null
		Set @SQL_Table2_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table2_SourceName))>0 and len(trim(@SQL_Table2_SourceValidFrom))=0 or @SQL_Table2_SourceValidFrom is null
		Set @SQL_Table2_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table2_SourceName))>0 and len(trim(@SQL_Table2_SourceValidTo))=0 or @SQL_Table2_SourceValidTo is null
		Set @SQL_Table2_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table2_SourceRowID)=0
		Set @SQL_Table2_SourceRowID=Concat('|x|',@SQL_Table2_SourceRowID)

	if len(trim(@SQL_Table3_SourceName))>0 and len(trim(@SQL_Table3_SourceDB))=0 or @SQL_Table3_SourceDB is null
		Set @SQL_Table3_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table3_SourceName))>0 and len(trim(@SQL_Table3_SourceSchema))=0 or @SQL_Table3_SourceSchema is null
		Set @SQL_Table3_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table3_SourceName))>0 and len(trim(@SQL_Table3_Connect_ID))=0 or @SQL_Table3_Connect_ID is null
		Set @SQL_Table3_Connect_ID=@SQL_Table1_Connect_ID3
	if len(trim(@SQL_Table3_SourceName))>0 and len(trim(@SQL_Table3_SourceRowID))=0 or @SQL_Table3_SourceRowID is null
		Set @SQL_Table3_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table3_SourceName))>0 and len(trim(@SQL_Table3_SourceValidFrom))=0 or @SQL_Table3_SourceValidFrom is null
		Set @SQL_Table3_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table3_SourceName))>0 and len(trim(@SQL_Table3_SourceValidTo))=0 or @SQL_Table3_SourceValidTo is null
		Set @SQL_Table3_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table3_SourceRowID)=0
		Set @SQL_Table3_SourceRowID=Concat('|x|',@SQL_Table3_SourceRowID)

	if len(trim(@SQL_Table4_SourceName))>0 and len(trim(@SQL_Table4_SourceDB))=0 or @SQL_Table4_SourceDB is null
		Set @SQL_Table4_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table4_SourceName))>0 and len(trim(@SQL_Table4_SourceSchema))=0 or @SQL_Table4_SourceSchema is null
		Set @SQL_Table4_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table4_SourceName))>0 and len(trim(@SQL_Table4_Connect_ID))=0 or @SQL_Table4_Connect_ID is null
		Set @SQL_Table4_Connect_ID=@SQL_Table1_Connect_ID4
	if len(trim(@SQL_Table4_SourceName))>0 and len(trim(@SQL_Table4_SourceRowID))=0 or @SQL_Table4_SourceRowID is null
		Set @SQL_Table4_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table4_SourceName))>0 and len(trim(@SQL_Table4_SourceValidFrom))=0 or @SQL_Table4_SourceValidFrom is null
		Set @SQL_Table4_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table4_SourceName))>0 and len(trim(@SQL_Table4_SourceValidTo))=0 or @SQL_Table4_SourceValidTo is null
		Set @SQL_Table4_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table4_SourceRowID)=0
		Set @SQL_Table4_SourceRowID=Concat('|x|',@SQL_Table4_SourceRowID)

	if len(trim(@SQL_Table5_SourceName))>0 and len(trim(@SQL_Table5_SourceDB))=0 or @SQL_Table5_SourceDB is null
		Set @SQL_Table5_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table5_SourceName))>0 and len(trim(@SQL_Table5_SourceSchema))=0 or @SQL_Table5_SourceSchema is null
		Set @SQL_Table5_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table5_SourceName))>0 and len(trim(@SQL_Table5_Connect_ID))=0 or @SQL_Table5_Connect_ID is null
		Set @SQL_Table5_Connect_ID=@SQL_Table1_Connect_ID5
	if len(trim(@SQL_Table5_SourceName))>0 and len(trim(@SQL_Table5_SourceRowID))=0 or @SQL_Table5_SourceRowID is null
		Set @SQL_Table5_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table5_SourceName))>0 and len(trim(@SQL_Table5_SourceValidFrom))=0 or @SQL_Table5_SourceValidFrom is null
		Set @SQL_Table5_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table5_SourceName))>0 and len(trim(@SQL_Table5_SourceValidTo))=0 or @SQL_Table5_SourceValidTo is null
		Set @SQL_Table5_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table5_SourceRowID)=0
		Set @SQL_Table5_SourceRowID=Concat('|x|',@SQL_Table5_SourceRowID)

	if len(trim(@SQL_Table6_SourceName))>0 and len(trim(@SQL_Table6_SourceDB))=0 or @SQL_Table6_SourceDB is null
		Set @SQL_Table6_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table6_SourceName))>0 and len(trim(@SQL_Table6_SourceSchema))=0 or @SQL_Table6_SourceSchema is null
		Set @SQL_Table6_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table6_SourceName))>0 and len(trim(@SQL_Table6_Connect_ID))=0 or @SQL_Table6_Connect_ID is null
		Set @SQL_Table6_Connect_ID=@SQL_Table1_Connect_ID6
	if len(trim(@SQL_Table6_SourceName))>0 and len(trim(@SQL_Table6_SourceRowID))=0 or @SQL_Table6_SourceRowID is null
		Set @SQL_Table6_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table6_SourceName))>0 and len(trim(@SQL_Table6_SourceValidFrom))=0 or @SQL_Table6_SourceValidFrom is null
		Set @SQL_Table6_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table6_SourceName))>0 and len(trim(@SQL_Table6_SourceValidTo))=0 or @SQL_Table6_SourceValidTo is null
		Set @SQL_Table6_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table6_SourceRowID)=0
		Set @SQL_Table6_SourceRowID=Concat('|x|',@SQL_Table6_SourceRowID)

	if len(trim(@SQL_Table7_SourceName))>0 and len(trim(@SQL_Table7_SourceDB))=0 or @SQL_Table7_SourceDB is null
		Set @SQL_Table7_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table7_SourceName))>0 and len(trim(@SQL_Table7_SourceSchema))=0 or @SQL_Table7_SourceSchema is null
		Set @SQL_Table7_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table7_SourceName))>0 and len(trim(@SQL_Table7_Connect_ID))=0 or @SQL_Table7_Connect_ID is null
		Set @SQL_Table7_Connect_ID=@SQL_Table1_Connect_ID7
	if len(trim(@SQL_Table7_SourceName))>0 and len(trim(@SQL_Table7_SourceRowID))=0 or @SQL_Table7_SourceRowID is null
		Set @SQL_Table7_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table7_SourceName))>0 and len(trim(@SQL_Table7_SourceValidFrom))=0 or @SQL_Table7_SourceValidFrom is null
		Set @SQL_Table7_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table7_SourceName))>0 and len(trim(@SQL_Table7_SourceValidTo))=0 or @SQL_Table7_SourceValidTo is null
		Set @SQL_Table7_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table7_SourceRowID)=0
		Set @SQL_Table7_SourceRowID=Concat('|x|',@SQL_Table7_SourceRowID)

	if len(trim(@SQL_Table8_SourceName))>0 and len(trim(@SQL_Table8_SourceDB))=0 or @SQL_Table8_SourceDB is null
		Set @SQL_Table8_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table8_SourceName))>0 and len(trim(@SQL_Table8_SourceSchema))=0 or @SQL_Table8_SourceSchema is null
		Set @SQL_Table8_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table8_SourceName))>0 and len(trim(@SQL_Table8_Connect_ID))=0 or @SQL_Table8_Connect_ID is null
		Set @SQL_Table8_Connect_ID=@SQL_Table1_Connect_ID8
	if len(trim(@SQL_Table8_SourceName))>0 and len(trim(@SQL_Table8_SourceRowID))=0 or @SQL_Table8_SourceRowID is null
		Set @SQL_Table8_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table8_SourceName))>0 and len(trim(@SQL_Table8_SourceValidFrom))=0 or @SQL_Table8_SourceValidFrom is null
		Set @SQL_Table8_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table8_SourceName))>0 and len(trim(@SQL_Table8_SourceValidTo))=0 or @SQL_Table8_SourceValidTo is null
		Set @SQL_Table8_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table8_SourceRowID)=0
		Set @SQL_Table8_SourceRowID=Concat('|x|',@SQL_Table8_SourceRowID)

	if len(trim(@SQL_Table9_SourceName))>0 and len(trim(@SQL_Table9_SourceDB))=0 or @SQL_Table9_SourceDB is null
		Set @SQL_Table9_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table9_SourceName))>0 and len(trim(@SQL_Table9_SourceSchema))=0 or @SQL_Table9_SourceSchema is null
		Set @SQL_Table9_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table9_SourceName))>0 and len(trim(@SQL_Table9_Connect_ID))=0 or @SQL_Table9_Connect_ID is null
		Set @SQL_Table9_Connect_ID=@SQL_Table1_Connect_ID9
	if len(trim(@SQL_Table9_SourceName))>0 and len(trim(@SQL_Table9_SourceRowID))=0 or @SQL_Table9_SourceRowID is null
		Set @SQL_Table9_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table9_SourceName))>0 and len(trim(@SQL_Table9_SourceValidFrom))=0 or @SQL_Table9_SourceValidFrom is null
		Set @SQL_Table9_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table9_SourceName))>0 and len(trim(@SQL_Table9_SourceValidTo))=0 or @SQL_Table9_SourceValidTo is null
		Set @SQL_Table9_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table9_SourceRowID)=0
		Set @SQL_Table9_SourceRowID=Concat('|x|',@SQL_Table9_SourceRowID)

	if len(trim(@SQL_Table10_SourceName))>0 and len(trim(@SQL_Table10_SourceDB))=0 or @SQL_Table10_SourceDB is null
		Set @SQL_Table10_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table10_SourceName))>0 and len(trim(@SQL_Table10_SourceSchema))=0 or @SQL_Table10_SourceSchema is null
		Set @SQL_Table10_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table10_SourceName))>0 and len(trim(@SQL_Table10_Connect_ID))=0 or @SQL_Table10_Connect_ID is null
		Set @SQL_Table10_Connect_ID=@SQL_Table1_Connect_ID10
	if len(trim(@SQL_Table10_SourceName))>0 and len(trim(@SQL_Table10_SourceRowID))=0 or @SQL_Table10_SourceRowID is null
		Set @SQL_Table10_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table10_SourceName))>0 and len(trim(@SQL_Table10_SourceValidFrom))=0 or @SQL_Table10_SourceValidFrom is null
		Set @SQL_Table10_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table10_SourceName))>0 and len(trim(@SQL_Table10_SourceValidTo))=0 or @SQL_Table10_SourceValidTo is null
		Set @SQL_Table10_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table10_SourceRowID)=0
		Set @SQL_Table10_SourceRowID=Concat('|x|',@SQL_Table10_SourceRowID)

	if len(trim(@SQL_Table11_SourceName))>0 and len(trim(@SQL_Table11_SourceDB))=0 or @SQL_Table11_SourceDB is null
		Set @SQL_Table11_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table11_SourceName))>0 and len(trim(@SQL_Table11_SourceSchema))=0 or @SQL_Table11_SourceSchema is null
		Set @SQL_Table11_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table11_SourceName))>0 and len(trim(@SQL_Table11_Connect_ID))=0 or @SQL_Table11_Connect_ID is null
		Set @SQL_Table11_Connect_ID=@SQL_Table1_Connect_ID11
	if len(trim(@SQL_Table11_SourceName))>0 and len(trim(@SQL_Table11_SourceRowID))=0 or @SQL_Table11_SourceRowID is null
		Set @SQL_Table11_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table11_SourceName))>0 and len(trim(@SQL_Table11_SourceValidFrom))=0 or @SQL_Table11_SourceValidFrom is null
		Set @SQL_Table11_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table11_SourceName))>0 and len(trim(@SQL_Table11_SourceValidTo))=0 or @SQL_Table11_SourceValidTo is null
		Set @SQL_Table11_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table11_SourceRowID)=0
		Set @SQL_Table11_SourceRowID=Concat('|x|',@SQL_Table11_SourceRowID)

	if len(trim(@SQL_Table12_SourceName))>0 and len(trim(@SQL_Table12_SourceDB))=0 or @SQL_Table12_SourceDB is null
		Set @SQL_Table12_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table12_SourceName))>0 and len(trim(@SQL_Table12_SourceSchema))=0 or @SQL_Table12_SourceSchema is null
		Set @SQL_Table12_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table12_SourceName))>0 and len(trim(@SQL_Table12_Connect_ID))=0 or @SQL_Table12_Connect_ID is null
		Set @SQL_Table12_Connect_ID=@SQL_Table1_Connect_ID12
	if len(trim(@SQL_Table12_SourceName))>0 and len(trim(@SQL_Table12_SourceRowID))=0 or @SQL_Table12_SourceRowID is null
		Set @SQL_Table12_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table12_SourceName))>0 and len(trim(@SQL_Table12_SourceValidFrom))=0 or @SQL_Table12_SourceValidFrom is null
		Set @SQL_Table12_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table12_SourceName))>0 and len(trim(@SQL_Table12_SourceValidTo))=0 or @SQL_Table12_SourceValidTo is null
		Set @SQL_Table12_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table12_SourceRowID)=0
		Set @SQL_Table12_SourceRowID=Concat('|x|',@SQL_Table12_SourceRowID)

	if len(trim(@SQL_Table13_SourceName))>0 and len(trim(@SQL_Table13_SourceDB))=0 or @SQL_Table13_SourceDB is null
		Set @SQL_Table13_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table13_SourceName))>0 and len(trim(@SQL_Table13_SourceSchema))=0 or @SQL_Table13_SourceSchema is null
		Set @SQL_Table13_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table13_SourceName))>0 and len(trim(@SQL_Table13_Connect_ID))=0 or @SQL_Table13_Connect_ID is null
		Set @SQL_Table13_Connect_ID=@SQL_Table1_Connect_ID13
	if len(trim(@SQL_Table13_SourceName))>0 and len(trim(@SQL_Table13_SourceRowID))=0 or @SQL_Table13_SourceRowID is null
		Set @SQL_Table13_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table13_SourceName))>0 and len(trim(@SQL_Table13_SourceValidFrom))=0 or @SQL_Table13_SourceValidFrom is null
		Set @SQL_Table13_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table13_SourceName))>0 and len(trim(@SQL_Table13_SourceValidTo))=0 or @SQL_Table13_SourceValidTo is null
		Set @SQL_Table13_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table13_SourceRowID)=0
		Set @SQL_Table13_SourceRowID=Concat('|x|',@SQL_Table13_SourceRowID)

	if len(trim(@SQL_Table14_SourceName))>0 and len(trim(@SQL_Table14_SourceDB))=0 or @SQL_Table14_SourceDB is null
		Set @SQL_Table14_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table14_SourceName))>0 and len(trim(@SQL_Table14_SourceSchema))=0 or @SQL_Table14_SourceSchema is null
		Set @SQL_Table14_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table14_SourceName))>0 and len(trim(@SQL_Table14_Connect_ID))=0 or @SQL_Table14_Connect_ID is null
		Set @SQL_Table14_Connect_ID=@SQL_Table1_Connect_ID14
	if len(trim(@SQL_Table14_SourceName))>0 and len(trim(@SQL_Table14_SourceRowID))=0 or @SQL_Table14_SourceRowID is null
		Set @SQL_Table14_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table14_SourceName))>0 and len(trim(@SQL_Table14_SourceValidFrom))=0 or @SQL_Table14_SourceValidFrom is null
		Set @SQL_Table14_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table14_SourceName))>0 and len(trim(@SQL_Table14_SourceValidTo))=0 or @SQL_Table14_SourceValidTo is null
		Set @SQL_Table14_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table14_SourceRowID)=0
		Set @SQL_Table14_SourceRowID=Concat('|x|',@SQL_Table14_SourceRowID)

	if len(trim(@SQL_Table15_SourceName))>0 and len(trim(@SQL_Table15_SourceDB))=0 or @SQL_Table15_SourceDB is null
		Set @SQL_Table15_SourceDB=@SQL_Table1_SourceDB
	if len(trim(@SQL_Table15_SourceName))>0 and len(trim(@SQL_Table15_SourceSchema))=0 or @SQL_Table15_SourceSchema is null
		Set @SQL_Table15_SourceSchema=@SQL_Table1_SourceSchema	
	if len(trim(@SQL_Table15_SourceName))>0 and len(trim(@SQL_Table15_Connect_ID))=0 or @SQL_Table15_Connect_ID is null
		Set @SQL_Table15_Connect_ID=@SQL_Table1_Connect_ID15
	if len(trim(@SQL_Table15_SourceName))>0 and len(trim(@SQL_Table15_SourceRowID))=0 or @SQL_Table15_SourceRowID is null
		Set @SQL_Table15_SourceRowID=@SQL_Table1_SourceRowID			
	if len(trim(@SQL_Table15_SourceName))>0 and len(trim(@SQL_Table15_SourceValidFrom))=0 or @SQL_Table15_SourceValidFrom is null
		Set @SQL_Table15_SourceValidFrom=@SQL_Table1_SourceValidFrom	
	if len(trim(@SQL_Table15_SourceName))>0 and len(trim(@SQL_Table15_SourceValidTo))=0 or @SQL_Table15_SourceValidTo is null
		Set @SQL_Table15_SourceValidTo=@SQL_Table1_SourceValidTo	
	if CHARINDEX('|x|',@SQL_Table15_SourceRowID)=0
		Set @SQL_Table15_SourceRowID=Concat('|x|',@SQL_Table15_SourceRowID)


	IF LEN(TRIM(@SQL_Table1_SourceString)) = 0 OR @SQL_Table1_SourceString IS NULL
		SET @SQL_Table1_SourceString = CONCAT(@SQL_Table1_SourceDB, '.', @SQL_Table1_SourceSchema, '.', @SQL_Table1_SourceName)

	SET @SQL_Table1_SourceString	= REPLACE(REPLACE(@SQL_Table1_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table2_SourceString)) = 0 OR @SQL_Table2_SourceString IS NULL
		SET @SQL_Table2_SourceString = CONCAT(@SQL_Table2_SourceDB, '.', @SQL_Table2_SourceSchema, '.', @SQL_Table2_SourceName)

	SET @SQL_Table2_SourceString	= REPLACE(REPLACE(@SQL_Table2_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table3_SourceString)) = 0 OR @SQL_Table3_SourceString IS NULL
		SET @SQL_Table3_SourceString = CONCAT(@SQL_Table3_SourceDB, '.', @SQL_Table3_SourceSchema, '.', @SQL_Table3_SourceName)

	SET @SQL_Table3_SourceString	= REPLACE(REPLACE(@SQL_Table3_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table4_SourceString)) = 0 OR @SQL_Table4_SourceString IS NULL
		SET @SQL_Table4_SourceString = CONCAT(@SQL_Table4_SourceDB, '.', @SQL_Table4_SourceSchema, '.', @SQL_Table4_SourceName)

	SET @SQL_Table4_SourceString	= REPLACE(REPLACE(@SQL_Table4_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table5_SourceString)) = 0 OR @SQL_Table5_SourceString IS NULL
		SET @SQL_Table5_SourceString = CONCAT(@SQL_Table5_SourceDB, '.', @SQL_Table5_SourceSchema, '.', @SQL_Table5_SourceName)

	SET @SQL_Table5_SourceString	= REPLACE(REPLACE(@SQL_Table5_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table6_SourceString)) = 0 OR @SQL_Table6_SourceString IS NULL
		SET @SQL_Table6_SourceString = CONCAT(@SQL_Table6_SourceDB, '.', @SQL_Table6_SourceSchema, '.', @SQL_Table6_SourceName)

	SET @SQL_Table6_SourceString	= REPLACE(REPLACE(@SQL_Table6_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table7_SourceString)) = 0 OR @SQL_Table7_SourceString IS NULL
		SET @SQL_Table7_SourceString = CONCAT(@SQL_Table7_SourceDB, '.', @SQL_Table7_SourceSchema, '.', @SQL_Table7_SourceName)

	SET @SQL_Table7_SourceString	= REPLACE(REPLACE(@SQL_Table7_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table8_SourceString)) = 0 OR @SQL_Table8_SourceString IS NULL
		SET @SQL_Table8_SourceString = CONCAT(@SQL_Table8_SourceDB, '.', @SQL_Table8_SourceSchema, '.', @SQL_Table8_SourceName)

	SET @SQL_Table8_SourceString	= REPLACE(REPLACE(@SQL_Table8_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table9_SourceString)) = 0 OR @SQL_Table9_SourceString IS NULL
		SET @SQL_Table9_SourceString = CONCAT(@SQL_Table9_SourceDB, '.', @SQL_Table9_SourceSchema, '.', @SQL_Table9_SourceName)

	SET @SQL_Table9_SourceString	= REPLACE(REPLACE(@SQL_Table9_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table10_SourceString)) = 0 OR @SQL_Table10_SourceString IS NULL
		SET @SQL_Table10_SourceString = CONCAT(@SQL_Table10_SourceDB, '.', @SQL_Table10_SourceSchema, '.', @SQL_Table10_SourceName)

	SET @SQL_Table10_SourceString	= REPLACE(REPLACE(@SQL_Table10_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table11_SourceString)) = 0 OR @SQL_Table11_SourceString IS NULL
		SET @SQL_Table11_SourceString = CONCAT(@SQL_Table11_SourceDB, '.', @SQL_Table11_SourceSchema, '.', @SQL_Table11_SourceName)

	SET @SQL_Table11_SourceString	= REPLACE(REPLACE(@SQL_Table11_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table12_SourceString)) = 0 OR @SQL_Table12_SourceString IS NULL
		SET @SQL_Table12_SourceString = CONCAT(@SQL_Table12_SourceDB, '.', @SQL_Table12_SourceSchema, '.', @SQL_Table12_SourceName)

	SET @SQL_Table12_SourceString	= REPLACE(REPLACE(@SQL_Table12_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table13_SourceString)) = 0 OR @SQL_Table13_SourceString IS NULL
		SET @SQL_Table13_SourceString = CONCAT(@SQL_Table13_SourceDB, '.', @SQL_Table13_SourceSchema, '.', @SQL_Table13_SourceName)

	SET @SQL_Table13_SourceString	= REPLACE(REPLACE(@SQL_Table13_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table14_SourceString)) = 0 OR @SQL_Table14_SourceString IS NULL
		SET @SQL_Table14_SourceString = CONCAT(@SQL_Table14_SourceDB, '.', @SQL_Table14_SourceSchema, '.', @SQL_Table14_SourceName)

	SET @SQL_Table14_SourceString	= REPLACE(REPLACE(@SQL_Table14_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_Table15_SourceString)) = 0 OR @SQL_Table15_SourceString IS NULL
		SET @SQL_Table15_SourceString = CONCAT(@SQL_Table15_SourceDB, '.', @SQL_Table15_SourceSchema, '.', @SQL_Table15_SourceName)

	SET @SQL_Table15_SourceString	= REPLACE(REPLACE(@SQL_Table15_SourceString, '[', ''), ']', '')

	IF LEN(TRIM(@SQL_TableTargetString)) = 0 OR @SQL_TableTargetString IS NULL
		SET @SQL_TableTargetString = CONCAT(@SQL_TableTargetDB, '.', @SQL_TableTargetSchema, '.', @SQL_TableTargetName)

	SET @SQL_TableTargetString	= REPLACE(REPLACE(@SQL_TableTargetString, '[', ''), ']', '')


	if LEN(@SQL_Table1_SourceFields)>3 
		Begin
			if CHARINDEX('.',@SQL_Table1_SourceFields)=0
				SET @SQL_Table1_SourceFields=concat(',|x|',replace(replace(@SQL_Table1_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table1_SourceFields),1)<>',' 
					SET @SQL_Table1_SourceFields=concat(',',@SQL_Table1_SourceFields)
		End
	Else
		SET @SQL_Table1_SourceFields=''
	if LEN(@SQL_Table2_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table2_SourceFields)=0
				SET @SQL_Table2_SourceFields=concat('|x|',replace(replace(@SQL_Table2_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table2_SourceFields),1)<>',' 
					SET @SQL_Table2_SourceFields=concat(',',@SQL_Table2_SourceFields)
		End
	Else 
		SET @SQL_Table2_SourceFields=''
	if LEN(@SQL_Table3_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table3_SourceFields)=0
				SET @SQL_Table3_SourceFields=concat('|x|',replace(replace(@SQL_Table3_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table3_SourceFields),1)<>',' 
					SET @SQL_Table3_SourceFields=concat(',',@SQL_Table3_SourceFields)
		End
	Else 
		SET @SQL_Table3_SourceFields=''
	if LEN(@SQL_Table4_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table4_SourceFields)=0
				SET @SQL_Table4_SourceFields=concat('|x|',replace(replace(@SQL_Table4_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table4_SourceFields),1)<>',' 
					SET @SQL_Table4_SourceFields=concat(',',@SQL_Table4_SourceFields)
		End
	Else 
		SET @SQL_Table4_SourceFields=''
	if LEN(@SQL_Table5_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table5_SourceFields)=0
				SET @SQL_Table5_SourceFields=concat('|x|',replace(replace(@SQL_Table5_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table5_SourceFields),1)<>',' 
					SET @SQL_Table5_SourceFields=concat(',',@SQL_Table5_SourceFields)
		End
	Else 
		SET @SQL_Table5_SourceFields=''
	if LEN(@SQL_Table6_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table6_SourceFields)=0
				SET @SQL_Table6_SourceFields=concat('|x|',replace(replace(@SQL_Table6_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table6_SourceFields),1)<>',' 
					SET @SQL_Table6_SourceFields=concat(',',@SQL_Table6_SourceFields)
		End
	Else 
		SET @SQL_Table6_SourceFields=''
	if LEN(@SQL_Table7_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table7_SourceFields)=0
				SET @SQL_Table7_SourceFields=concat('|x|',replace(replace(@SQL_Table7_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table7_SourceFields),1)<>',' 
					SET @SQL_Table7_SourceFields=concat(',',@SQL_Table7_SourceFields)
		End
	Else 
		SET @SQL_Table7_SourceFields=''
	if LEN(@SQL_Table8_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table8_SourceFields)=0
				SET @SQL_Table8_SourceFields=concat('|x|',replace(replace(@SQL_Table8_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table8_SourceFields),1)<>',' 
					SET @SQL_Table8_SourceFields=concat(',',@SQL_Table8_SourceFields)
		End
	Else 
		SET @SQL_Table8_SourceFields=''
	if LEN(@SQL_Table9_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table9_SourceFields)=0
				SET @SQL_Table9_SourceFields=concat('|x|',replace(replace(@SQL_Table9_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table9_SourceFields),1)<>',' 
					SET @SQL_Table9_SourceFields=concat(',',@SQL_Table9_SourceFields)
		End
	Else 
		SET @SQL_Table9_SourceFields=''
	if LEN(@SQL_Table10_SourceFields)>3 
		Begin
			if CHARINDEX('.',@SQL_Table10_SourceFields)=0
				SET @SQL_Table10_SourceFields=concat('|x|',replace(replace(@SQL_Table10_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table10_SourceFields),1)<>',' 
					SET @SQL_Table10_SourceFields=concat(',',@SQL_Table10_SourceFields)
		End
	Else 
		SET @SQL_Table10_SourceFields=''
	if LEN(@SQL_Table11_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table11_SourceFields)=0
				SET @SQL_Table11_SourceFields=concat('|x|',replace(replace(@SQL_Table11_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table11_SourceFields),1)<>',' 
					SET @SQL_Table11_SourceFields=concat(',',@SQL_Table11_SourceFields)
		End
	Else 
		SET @SQL_Table11_SourceFields=''
	if LEN(@SQL_Table12_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table12_SourceFields)=0
				SET @SQL_Table12_SourceFields=concat('|x|',replace(replace(@SQL_Table12_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table12_SourceFields),1)<>',' 
					SET @SQL_Table12_SourceFields=concat(',',@SQL_Table12_SourceFields)
		End
	Else 
		SET @SQL_Table12_SourceFields=''
	if LEN(@SQL_Table13_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table13_SourceFields)=0
				SET @SQL_Table13_SourceFields=concat('|x|',replace(replace(@SQL_Table13_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table13_SourceFields),1)<>',' 
					SET @SQL_Table13_SourceFields=concat(',',@SQL_Table13_SourceFields)
		End
	Else 
		SET @SQL_Table13_SourceFields=''
	if LEN(@SQL_Table14_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table14_SourceFields)=0
				SET @SQL_Table14_SourceFields=concat('|x|',replace(replace(@SQL_Table14_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table14_SourceFields),1)<>',' 
					SET @SQL_Table14_SourceFields=concat(',',@SQL_Table14_SourceFields)
		End
	Else 
		SET @SQL_Table14_SourceFields=''
	if LEN(@SQL_Table15_SourceFields)>3  
		Begin
			if CHARINDEX('.',@SQL_Table15_SourceFields)=0
				SET @SQL_Table15_SourceFields=concat('|x|',replace(replace(@SQL_Table15_SourceFields,'|x|',''),',',',|x|'))
			else
				if left(trim(@SQL_Table15_SourceFields),1)<>',' 
					SET @SQL_Table15_SourceFields=concat(',',@SQL_Table15_SourceFields)
		End
	Else 
		SET @SQL_Table15_SourceFields=''
		
	if LEN(trim(@SQL_TableTargetRowID1))<3 or @SQL_TableTargetRowID1 is null 
		Set @SQL_TableTargetRowID1=CONCAT('|x|RowID_',replace(@SQL_Table1_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID2))<3 or @SQL_TableTargetRowID2 is null 
		Set @SQL_TableTargetRowID2=CONCAT('|x|RowID_',replace(@SQL_Table2_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID3))<3 or @SQL_TableTargetRowID3 is null 
		Set @SQL_TableTargetRowID3=CONCAT('|x|RowID_',replace(@SQL_Table3_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID4))<3 or @SQL_TableTargetRowID4 is null 
		Set @SQL_TableTargetRowID4=CONCAT('|x|RowID_',replace(@SQL_Table4_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID5))<3 or @SQL_TableTargetRowID5 is null 
		Set @SQL_TableTargetRowID5=CONCAT('|x|RowID_',replace(@SQL_Table5_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID6))<3 or @SQL_TableTargetRowID6 is null 
		Set @SQL_TableTargetRowID6=CONCAT('|x|RowID_',replace(@SQL_Table6_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID7))<3 or @SQL_TableTargetRowID7 is null 
		Set @SQL_TableTargetRowID7=CONCAT('|x|RowID_',replace(@SQL_Table7_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID8))<3 or @SQL_TableTargetRowID8 is null 
		Set @SQL_TableTargetRowID8=CONCAT('|x|RowID_',replace(@SQL_Table8_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID9))<3 or @SQL_TableTargetRowID9 is null 
		Set @SQL_TableTargetRowID9=CONCAT('|x|RowID_',replace(@SQL_Table9_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID10))<3 or @SQL_TableTargetRowID10 is null 
		Set @SQL_TableTargetRowID10=CONCAT('|x|RowID_',replace(@SQL_Table10_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID11))<3 or @SQL_TableTargetRowID11 is null 
		Set @SQL_TableTargetRowID11=CONCAT('|x|RowID_',replace(@SQL_Table11_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID12))<3 or @SQL_TableTargetRowID12 is null 
		Set @SQL_TableTargetRowID12=CONCAT('|x|RowID_',replace(@SQL_Table12_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID13))<3 or @SQL_TableTargetRowID13 is null 
		Set @SQL_TableTargetRowID13=CONCAT('|x|RowID_',replace(@SQL_Table13_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID14))<3 or @SQL_TableTargetRowID14 is null 
		Set @SQL_TableTargetRowID14=CONCAT('|x|RowID_',replace(@SQL_Table14_SourceName,'|x|',''))
	if LEN(trim(@SQL_TableTargetRowID15))<3 or @SQL_TableTargetRowID15 is null 
		Set @SQL_TableTargetRowID15=CONCAT('|x|RowID_',replace(@SQL_Table15_SourceName,'|x|',''))

	if LEN(@SQL_Table1_ID)=0 or @SQL_Table1_ID is null
		begin
			SET @StepPraefix='P10'
			SET @SQL_Table1_ID=Null
			SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
			SET @StepText=Concat('','ID der Faktentabelle [',@SQL_Table1_SourceString,'] suchen und als @SQL_Table1_ID speichern.')
			SET @SQL=Concat('
							SET @SQL_Table1_ID=isnull((Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table1_SourceString,'U')),'),'''')			
							')

			EXEC sp_EXECutesql @SQL, N'@SQL_Table1_ID nvarchar(200) OUT', @SQL_Table1_ID OUT;
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
		end

	if @Fehler>0 or @SQL_Table1_ID is null or LEN(@SQL_Table1_ID)=0
		begin
			Print @SQL_Table1_SourceString
			Print @SQL
			Print 'Keine TableID gefunden!!!'
			goto Fehlermarke
		end

	if LEN(@SQL_Table1_ID)>0 and len(@SQL_Table1_SourceString)>2 and len(@SQL_Table1_SourceValidTo)>0 and len(@SQL_Table1_SourceValidFrom)>0 and len(@SQL_TableTargetRowID1)>0 and LEN(@SQL_Table1_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table1_SourceString, ''), 'U') IS NOT NULL 
		Set @Table1_Valid=1 else SET @Table1_Valid=0
	if UPPER(@SQL_Table2_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID2)>0 and len(@SQL_Table2_Connect_ID)>0 and len(@SQL_Table2_SourceString)>2 and len(@SQL_Table2_SourceValidTo)>0 and len(@SQL_Table2_SourceValidFrom)>0 and len(@SQL_TableTargetRowID2)>0 and LEN(@SQL_Table2_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table2_SourceString, ''), 'U') IS NOT NULL 
		Set @Table2_Valid=1 else SET @Table2_Valid=0
	if UPPER(@SQL_Table3_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID3)>0 and len(@SQL_table3_Connect_ID)>0 and len(@SQL_table3_SourceString)>2 and len(@SQL_table3_SourceValidTo)>0 and len(@SQL_table3_SourceValidFrom)>0 and len(@SQL_TableTargetRowID3)>0 and LEN(@SQL_Table3_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table3_SourceString, ''), 'U') IS NOT NULL 
		Set @Table3_Valid=1 else SET @Table3_Valid=0
	if UPPER(@SQL_Table4_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID4)>0 and len(@SQL_table4_Connect_ID)>0 and len(@SQL_table4_SourceString)>2 and len(@SQL_table4_SourceValidTo)>0 and len(@SQL_table4_SourceValidFrom)>0 and len(@SQL_TableTargetRowID4)>0 and LEN(@SQL_Table4_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table4_SourceString, ''), 'U') IS NOT NULL 
		Set @Table4_Valid=1 else SET @Table4_Valid=0
	if UPPER(@SQL_Table5_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID5)>0 and len(@SQL_table5_Connect_ID)>0 and len(@SQL_table5_SourceString)>2 and len(@SQL_table5_SourceValidTo)>0 and len(@SQL_table5_SourceValidFrom)>0 and len(@SQL_TableTargetRowID5)>0 and LEN(@SQL_Table5_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table5_SourceString, ''), 'U') IS NOT NULL 
		Set @Table5_Valid=1 else SET @Table5_Valid=0
	if UPPER(@SQL_Table6_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID6)>0 and len(@SQL_table6_Connect_ID)>0 and len(@SQL_table6_SourceString)>2 and len(@SQL_table6_SourceValidTo)>0 and len(@SQL_table6_SourceValidFrom)>0 and len(@SQL_TableTargetRowID6)>0 and LEN(@SQL_Table6_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table6_SourceString, ''), 'U') IS NOT NULL 
		Set @Table6_Valid=1 else SET @Table6_Valid=0
	if UPPER(@SQL_Table7_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID7)>0 and len(@SQL_table7_Connect_ID)>0 and len(@SQL_table7_SourceString)>2 and len(@SQL_table7_SourceValidTo)>0 and len(@SQL_table7_SourceValidFrom)>0 and len(@SQL_TableTargetRowID7)>0 and LEN(@SQL_Table7_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table7_SourceString, ''), 'U') IS NOT NULL 
		Set @Table7_Valid=1 else SET @Table7_Valid=0
	if UPPER(@SQL_Table8_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID8)>0 and len(@SQL_table8_Connect_ID)>0 and len(@SQL_table8_SourceString)>2 and len(@SQL_table8_SourceValidTo)>0 and len(@SQL_table8_SourceValidFrom)>0 and len(@SQL_TableTargetRowID8)>0 and LEN(@SQL_Table8_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table8_SourceString, ''), 'U') IS NOT NULL 
		Set @Table8_Valid=1 else SET @Table8_Valid=0
	if UPPER(@SQL_Table9_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID9)>0 and len(@SQL_table9_Connect_ID)>0 and len(@SQL_table9_SourceString)>2 and len(@SQL_table9_SourceValidTo)>0 and len(@SQL_table9_SourceValidFrom)>0 and len(@SQL_TableTargetRowID9)>0 and LEN(@SQL_Table9_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table9_SourceString, ''), 'U') IS NOT NULL 
		Set @Table9_Valid=1 else SET @Table9_Valid=0
	if UPPER(@SQL_Table10_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID10)>0 and len(@SQL_table10_Connect_ID)>0 and len(@SQL_table10_SourceString)>2 and len(@SQL_table10_SourceValidTo)>0 and len(@SQL_table10_SourceValidFrom)>0 and len(@SQL_TableTargetRowID10)>0 and LEN(@SQL_Table10_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table10_SourceString, ''), 'U') IS NOT NULL 
		Set @Table10_Valid=1 else SET @Table10_Valid=0
	if UPPER(@SQL_Table11_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID11)>0 and len(@SQL_Table11_Connect_ID)>0 and len(@SQL_Table11_SourceString)>2 and len(@SQL_Table11_SourceValidTo)>0 and len(@SQL_Table11_SourceValidFrom)>0 and len(@SQL_TableTargetRowID12)>0 and LEN(@SQL_Table11_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table11_SourceString, ''), 'U') IS NOT NULL 
		Set @Table11_Valid=1 else SET @Table11_Valid=0
	if UPPER(@SQL_Table12_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID12)>0 and len(@SQL_Table12_Connect_ID)>0 and len(@SQL_Table12_SourceString)>2 and len(@SQL_Table12_SourceValidTo)>0 and len(@SQL_Table12_SourceValidFrom)>0 and len(@SQL_TableTargetRowID12)>0 and LEN(@SQL_Table12_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table12_SourceString, ''), 'U') IS NOT NULL 
		Set @Table12_Valid=1 else SET @Table12_Valid=0
	if UPPER(@SQL_Table13_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID13)>0 and len(@SQL_Table13_Connect_ID)>0 and len(@SQL_Table13_SourceString)>2 and len(@SQL_Table13_SourceValidTo)>0 and len(@SQL_Table13_SourceValidFrom)>0 and len(@SQL_TableTargetRowID13)>0 and LEN(@SQL_Table13_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table13_SourceString, ''), 'U') IS NOT NULL 
		Set @Table13_Valid=1 else SET @Table13_Valid=0
	if UPPER(@SQL_Table14_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID14)>0 and len(@SQL_Table14_Connect_ID)>0 and len(@SQL_Table14_SourceString)>2 and len(@SQL_Table14_SourceValidTo)>0 and len(@SQL_Table14_SourceValidFrom)>0 and len(@SQL_TableTargetRowID14)>0 and LEN(@SQL_Table14_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table14_SourceString, ''), 'U') IS NOT NULL 
		Set @Table14_Valid=1 else SET @Table14_Valid=0
	if UPPER(@SQL_Table15_SourceJoinTyp) in ('LEFT','INNER') and len(@SQL_Table1_Connect_ID15)>0 and len(@SQL_Table15_Connect_ID)>0 and len(@SQL_Table15_SourceString)>2 and len(@SQL_Table15_SourceValidTo)>0 and len(@SQL_Table15_SourceValidFrom)>0 and len(@SQL_TableTargetRowID15)>0 and LEN(@SQL_Table15_SourceName)>0 and OBJECT_ID(Concat(@SQL_Table15_SourceString, ''), 'U') IS NOT NULL 
		Set @Table15_Valid=1 else SET @Table15_Valid=0

	SET @SQL=Concat('Use ',@SQL_TableTargetDB);
	EXEC(@SQL);

	Execute dbo.Konfiguration @SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,  @SQL_TableLoggingString=@SQL_TableLoggingString, @SQL_TableTabStatusString=@SQL_TableTabStatusString, @SQL_TableQlikLoadString=@SQL_TableQlikLoadString, @SQL_TableRelationTreeString=@SQL_TableRelationTreeString, @Datenweg=@Datenweg OUTPUT; 

	If @TEMPPraefix='New' 
		Select @TEMPPraefix=cast(rand()*cast(Getdate() as int)*10000 as int)

	IF OBJECT_ID(@SQL_TableTargetString, 'U') IS NULL 
		Begin 
			SET @Datenweg=1
			PRINT 'Notwendige Daten für den FastTrack sind weg!'
		End
	else
		Begin
			SET @Datenweg=0
		end

    Print 'Start Logging'

    -- Erstellt eine temporäre Prozedur, die die Standardparameter automatisch setzt
    SET @SQL = CONCAT('
        CREATE PROCEDURE #LogStep
            @LogID                  AS BigInt           = NULL OUTPUT,
            @LogTableName           AS nVarChar(200)    = '''',
            @LogTableTime           AS DateTime2         = NULL,
            @LogTableProcess        AS nVarChar(200)    = '''',
            @LogTableProcessMode    AS nVarChar(50)     = '''',
            @LogTableProcessStatus  AS nVarChar(20)     = ''PROCESS'',
            @LogStep                AS nVarChar(20)     = '''',
            @LogStepText            AS nVarChar(500)    = '''',
            @LogStepStart           AS DateTime2         = NULL,
            @LogStepEnd             AS DateTime2         = NULL,
            @LogStepSQL             AS VarChar(max)     = '''',
            @LogStepSQL1            AS VarChar(max)     = '''',
            @LogStepSQL2            AS VarChar(max)     = '''',
            @LogStepSQL3            AS VarChar(max)     = '''',
            @LogStepSQL4            AS VarChar(max)     = '''',
            @LogStepSQL5            AS VarChar(max)     = '''',
            @LogStepSQL6            AS VarChar(max)     = '''',
            @LogStepSQL7            AS VarChar(max)     = '''',
            @LogStepSQL8            AS VarChar(max)     = '''',
            @LogStepSQL9            AS VarChar(max)     = '''',
            @LogStepSQL10           AS VarChar(max)     = '''',
            @LogStepRows            AS BigInt           = 0,
            @LogStepStatus          AS nVarChar(200)    = ''FINISHED'',
            @LogStepError           AS Int              = NULL,
            @LogStepErrorText       AS nVarChar(4000)   = '''',
            @LogTime                AS DateTime2         = NULL,
            @LogUser                AS nVarChar(100)    = NULL
	    AS
            BEGIN
                -- eigentliche Logging-Prozedur aufrufen
                EXEC dbo.Logging
                    -- Feste Parameter, die der Wrapper automatisch setzt
                    @SQL_TableLoggingString      = ''', @SQL_TableLoggingString, ''',
                    @SQL_TableRelationTreeString = ''', @SQL_TableRelationTreeString, ''',

                    -- Parameter, die vom Aufruf durchgereicht werden
                    @LogID                  = @LogID OUTPUT,
                    @LogTableName           = @LogTableName,
                    @LogTableTime           = @LogTableTime,
                    @LogTableProcess        = @LogTableProcess,
                    @LogTableProcessMode    = @LogTableProcessMode,
                    @LogTableProcessStatus  = @LogTableProcessStatus,
                    @LogStep                = @LogStep,
                    @LogStepText            = @LogStepText,
                    @LogStepStart           = @LogStepStart,
                    @LogStepEnd             = @LogStepEnd,
                    @LogStepSQL             = @LogStepSQL,
                    @LogStepSQL1            = @LogStepSQL1,
                    @LogStepSQL2            = @LogStepSQL2,
                    @LogStepSQL3            = @LogStepSQL3,
                    @LogStepSQL4            = @LogStepSQL4,
                    @LogStepSQL5            = @LogStepSQL5,
                    @LogStepSQL6            = @LogStepSQL6,
                    @LogStepSQL7            = @LogStepSQL7,
                    @LogStepSQL8            = @LogStepSQL8,
                    @LogStepSQL9            = @LogStepSQL9,
                    @LogStepSQL10           = @LogStepSQL10,
                    @LogStepRows            = @LogStepRows,
                    @LogStepStatus          = @LogStepStatus,
                    @LogStepError           = @LogStepError,
                    @LogStepErrorText       = @LogStepErrorText,
                    @LogTime                = @LogTime,
                    @LogUser                = @LogUser;
            END
	');
    IF OBJECT_ID('tempdb..#LogStep') IS NOT NULL
        DROP PROCEDURE #LogStep;
    EXEC(@SQL);

	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	Set @SQL= concat('
					Zyklus				:',@DaysToFullLoad,'
					TestDurchLauf		:',@TestLoop,'
					MaxDelay			:',@MaxDelay,'
					MaxDelayTimestamp	:',@MaxDelayTimestamp,'
					Delta				:',@DeltaDays,'
					Fullload			:',@FullloadYears,'
					Ladeverfahren		:',@Ladeverfahren,'
					TEMPPraefix			:',@TEMPPraefix,'
					TEMPLoeschen		:',@TEMPLoeschen,'
					gueltig_von			:',Replace(@SQL_TableTargetValidFrom,'|x|',''),'
					gueltig_bis			:',Replace(@SQL_TableTargetValidTo,'|x|',''),'
					Target Tabelle		:',@SQL_TableTargetString,'
					Logging Tabelle		:',@SQL_TableLoggingString,'
					Status Tabelle		:',@SQL_TableTabStatusString,'
					QlikLoad Tabelle	:',@SQL_TableQlikLoadString,'
					TargetString		:',@SQL_TableLoggingString,'
					@Table1_Valid		:',@SQL_Table1_SourceString,' (valid=',@Table1_Valid,')
					@Table2_Valid		:',@SQL_Table2_SourceString,' (valid=',@Table2_Valid,')
					@Table3_Valid		:',@SQL_Table3_SourceString,' (valid=',@Table3_Valid,')
					@Table4_Valid		:',@SQL_Table4_SourceString,' (valid=',@Table4_Valid,')
					@Table5_Valid		:',@SQL_Table5_SourceString,' (valid=',@Table5_Valid,')
					@Table6_Valid		:',@SQL_Table6_SourceString,' (valid=',@Table6_Valid,')
					@Table7_Valid		:',@SQL_Table7_SourceString,' (valid=',@Table7_Valid,')
					@Table8_Valid		:',@SQL_Table8_SourceString,' (valid=',@Table8_Valid,')
					@Table9_Valid		:',@SQL_Table9_SourceString,' (valid=',@Table9_Valid,')
					@Table10_Valid		:',@SQL_Table10_SourceString,' (valid=',@Table10_Valid,')
					@Table11_Valid		:',@SQL_Table11_SourceString,' (valid=',@Table11_Valid,')
					@Table12_Valid		:',@SQL_Table12_SourceString,' (valid=',@Table12_Valid,')
					@Table13_Valid		:',@SQL_Table13_SourceString,' (valid=',@Table13_Valid,')
					@Table14_Valid		:',@SQL_Table14_SourceString,' (valid=',@Table14_Valid,')
					@Table15_Valid		:',@SQL_Table15_SourceString,' (valid=',@Table15_Valid,')
					')

	Execute #LogStep @LogID=@LogID Output,
						@LogTableName=@SQL_TableTargetString,
						@LogTableProcess='TabJoin',
						@LogTableProcessMode=@Ladeverfahren,
						@LogTableProcessStatus='START',
						@LogStep='START',
						@LogStepText='START',
						@LogStepStart=@Start,
						@LogStepSQL=@SQL,
						@LogStepRows=0,
						@LogStepStatus='START'

	if @Fehler>0
		goto Fehlermarke


	if @Table1_Valid + @Table2_Valid + @Table3_Valid + @Table4_Valid + @Table5_Valid + @Table6_Valid + @Table7_Valid + @Table8_Valid + @Table9_Valid + @Table10_Valid + @Table11_Valid + @Table12_Valid + @Table13_Valid + @Table14_Valid + @Table15_Valid =0
		Begin
			SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
			SET @SQL = CONCAT('Keine valide Datengrundlage!
			@Table1_Valid= ',@Table1_Valid,'
			@Table2_Valid= ',@Table2_Valid,'
			@Table3_Valid= ',@Table3_Valid,'
			@Table4_Valid= ',@Table4_Valid,'
			@Table5_Valid= ',@Table5_Valid,'
			@Table6_Valid= ',@Table6_Valid,'
			@Table7_Valid= ',@Table7_Valid,'
			@Table8_Valid= ',@Table8_Valid,'
			@Table9_Valid= ',@Table9_Valid,'
			@Table10_Valid= ',@Table10_Valid,'
			@Table11_Valid= ',@Table11_Valid,'
			@Table12_Valid= ',@Table12_Valid,'
			@Table13_Valid= ',@Table13_Valid,'
			@Table14_Valid= ',@Table14_Valid,'
			@Table15_Valid= ',@Table15_Valid)
			PRINT @SQL
			
			Set @Fehler=99992
			goto Fehlermarke
		end

	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	SET @StepText=Concat('Abrufen des letzten Full-Loads für die Target-Tabelle ',@SQL_TableTargetString,' aus der Log-Tabelle ', @SQL_TableLoggingString,'.')
	SET @SQL=Concat('SELECT @LastFullLoad = (Select max(LogTableTime) as Zeitstempel 
								from ',@SQL_TableLoggingString,'
								where LogTableName=''', @SQL_TableTargetString, ''' and upper(LogTableProcessMode) in (''FULL'',''F'') and upper(LogTableProcessStatus)=''FINISHED'');
					 SELECT @LastLoad = (Select max(LogTableTime) as Zeitstempel 
								from ',@SQL_TableLoggingString,'
								where LogTableName=''', @SQL_TableTargetString, ''' and upper(LogTableProcessStatus)=''FINISHED'');

					With Baum
					as (
						SELECT t1.SourceObjectID as WurzelID
								,cast(concat(t1.[SourceTableDB],''.'',t1.[SourceTableSchema],''.'',t1.[SourceTableName]) as nvarchar(1000)) as Pfad
								,concat(t1.[SourceTableDB],''.'',t1.[SourceTableSchema],''.'',t1.[SourceTableName]) as Tab
								,1 as Ebene
								,t1.[SourceUpdate]
								,t1.SourceObjectID
								,t1.[StatusText]
						FROM ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableRelationTreeName,' t1
							left join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableRelationTreeName,' t2 on t2.[TargetTableDB]=t1.[SourceTableDB] and t2.[TargetTableSchema]=t1.[SourceTableSchema] and t2.[TargetTableName]=t1.[SourceTableName]
						where t2.[SourceTableDB] is null
						union all
						SELECT t2.WurzelID
								,cast(concat(t2.Pfad,''|'',t1.[TargetTableDB],''.'',t1.[TargetTableSchema],''.'',t1.[TargetTableName]) as nvarchar(1000))   as Pfad
								,concat(t1.[TargetTableDB],''.'',t1.[TargetTableSchema],''.'',t1.[TargetTableName]) as Tab
								,Ebene+1 as Ebene
								,t1.[SourceUpdate]
								,t1.SourceObjectID
								,t1.[StatusText]
						FROM ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableRelationTreeName,' t1
						join Baum t2 on concat(t1.[SourceTableDB],''.'',t1.[SourceTableSchema],''.'',t1.[SourceTableName]) =t2.Tab
						)
					Select @TableLastUpdate=(Select max(isnull(t2.last_user_update,t1.modify_date)) as Datum
											from ',@SQL_TableSourceSYSDB,'.sys.tables t1
												left join ',@SQL_TableSourceSYSDB,'.SYS.DM_DB_INDEX_USAGE_STATS t2 on t1.object_id=t2.object_id 
											where t1.object_id in (Select distinct WurzelID from Baum where Tab=''',@SQL_TableTargetString,''') 
											)
					')

	EXEC sp_EXECutesql @SQL, N'@LastFullLoad DateTime2 OUT,@LastLoad DateTime2 OUT,@TableLastUpdate DateTime2 OUT', @LastFullLoad=@LastFullLoad OUT,@LastLoad=@LastLoad OUT, @TableLastUpdate=@TableLastUpdate OUT;

	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep='P10', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke	

	If @FullloadYears <0 or @FullloadYears>20 or @FullloadYears is Null
		Set @FullloadYears=5

	IF (isnull(@LastLoad,cast('1.1.1990' as DateTime2))>isnull(@TableLastUpdate,cast('31.12.2099' as DateTime2)) or isnull(@LastLoad,cast('1.1.1990' as DateTime2)) >@MaxDelayTimestamp) and @Ladeverfahren<>'FN'
		Begin
			Set @Fehler=99993
			Set @FehlerText= concat('Zieldatei [',@SQL_TableTargetName,'] ist noch aktuell.
			@LastLoad=			', convert(nvarchar, @LastLoad, 113),'
			@TableLastUpdate=	', convert(nvarchar, @TableLastUpdate, 113),'
			@MaxDelayTimestamp=	', convert(nvarchar, @MaxDelayTimestamp, 113), '
			@Ladeverfahren=		', @Ladeverfahren)
			Print concat('Abbruch!!!!: ',@Fehler)
			Print @FehlerText
			goto Fehlermarke
		End	

	PRINT 'Start Datenload: ' + convert(nvarchar, @Start, 113);
	PRINT 'Datenstand letzter Load: ' + convert(nvarchar, @LastLoad, 113);
	PRINT 'Datenstand letzter Fullload: ' + convert(nvarchar, @LastFullLoad, 113);

	if (dateadd(d,@DaysToFullLoad, @LastFullLoad)<Getdate() 
		or @Datenweg=1 
		or @LastUpdate is null
		or @LastLoad is null
		or @LastFullLoad is null
		or @Ladeverfahren='F'
		) 
		and @FullloadYears <> 0
		and @Ladeverfahren<>'D'
		Begin 
			SET @Ladeverfahren='F'
			PRINT 'Starte Fullload'
		End
	else
		Begin
			SET @Ladeverfahren='D'
			PRINT 'Starte Fasttrack'
		End

XP10:
	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='XP10'
	SET @Liste_ConnectingFields=Null
	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	SET @StepText=Concat('','Erstellt die @Liste_ConnectingFields mit allen tatsächlich verfügbaren Spalten aus der SourceTable ','')
	SET @SQL=Concat('SELECT @Liste_ConnectingFields=COALESCE(@Liste_ConnectingFields+N'','', N'''') + ''|x|'' + t1.Spalte
						from (
							SELECT distinct replace(cast(value as nvarchar(100)),''|x|'','''') as Spalte 
							FROM STRING_SPLIT(''',CONCAT(@SQL_Table1_ID,',',@SQL_Table1_Connect_ID2,',',@SQL_Table1_Connect_ID3,',',@SQL_Table1_Connect_ID4,',',@SQL_Table1_Connect_ID5,',',@SQL_Table1_Connect_ID6,',',@SQL_Table1_Connect_ID7,',',
														 @SQL_Table1_Connect_ID8,',',@SQL_Table1_Connect_ID9,',',@SQL_Table1_Connect_ID10,',',@SQL_Table1_Connect_ID11,',',@SQL_Table1_Connect_ID12,',',@SQL_Table1_Connect_ID13,',',
														 @SQL_Table1_Connect_ID14,',',@SQL_Table1_Connect_ID15
														 ),''', '','')
							where len(value)>3
							 ) t1
						join (	
											SELECT Distinct c.name as Spalte, typ.name as Spaltentyp, c.max_length as Spaltenlaenge
											from ',@SQL_TableTargetDB,'.sys.columns c
												join ',@SQL_TableTargetDB,'.sys.tables tab ON c.object_id=tab.object_id
												join ',@SQL_TableTargetDB,'.sys.types typ ON c.user_type_id=typ.user_type_id
											WHERE tab.object_id = object_id(''',@SQL_Table1_SourceString,''',''U'')
												and not c.name like ''',replace(@SQL_TableTargetValidTo,'|x|',''),'%'' and not c.name like ''',replace(@SQL_TableTargetValidFrom,'|x|',''),'%''  and c.name <> ''Rang'' and c.name<>''SchluesselID''
											) t2 on t1.Spalte=t2.Spalte
						order by t1.Spalte')

	EXEC sp_EXECutesql @SQL, N'@Liste_ConnectingFields nvarchar(max) OUT', @Liste_ConnectingFields OUT;
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler
	
	if @Fehler>0
		goto Fehlermarke

XP20:
	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='XP20'
	SET @Liste_TableString=Null
	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	SET @StepText=Concat('','Erstellt @Liste_TableString mit notwendigen Informationen aus den Übergabeparemetern','')
	SET @SQL=Concat('
					with Aufteilung 
						as (
							SELECT value as Spalte, cast(left(value,2) as int) as Position
							FROM STRING_SPLIT(''',Replace(CONCAT('01'
									,case when @Table2_Valid>0 then CONCAT(',02',@SQL_Table2_SourceString,'%',isnull(@SQL_Use_Table2_ID,0),':',@SQL_Table2_SourceJoinTyp,'#',@SQL_Table2_Connect_ID,'=',@SQL_Table1_Connect_ID2,'>',@SQL_Table2_SourceValidFrom,'<',@SQL_Table2_SourceValidTo) else '' end
									,case when @Table3_Valid>0 then CONCAT(',03',@SQL_Table3_SourceString,'%',isnull(@SQL_Use_Table3_ID,0),':',@SQL_Table3_SourceJoinTyp,'#',@SQL_Table3_Connect_ID,'=',@SQL_Table1_Connect_ID3,'>',@SQL_Table3_SourceValidFrom,'<',@SQL_Table3_SourceValidTo) else '' end
									,case when @Table4_Valid>0 then CONCAT(',04',@SQL_Table4_SourceString,'%',isnull(@SQL_Use_Table4_ID,0),':',@SQL_Table4_SourceJoinTyp,'#',@SQL_Table4_Connect_ID,'=',@SQL_Table1_Connect_ID4,'>',@SQL_Table4_SourceValidFrom,'<',@SQL_Table4_SourceValidTo) else '' end
									,case when @Table5_Valid>0 then CONCAT(',05',@SQL_Table5_SourceString,'%',isnull(@SQL_Use_Table5_ID,0),':',@SQL_Table5_SourceJoinTyp,'#',@SQL_Table5_Connect_ID,'=',@SQL_Table1_Connect_ID5,'>',@SQL_Table5_SourceValidFrom,'<',@SQL_Table5_SourceValidTo) else '' end
									,case when @Table6_Valid>0 then CONCAT(',06',@SQL_Table6_SourceString,'%',isnull(@SQL_Use_Table6_ID,0),':',@SQL_Table6_SourceJoinTyp,'#',@SQL_Table6_Connect_ID,'=',@SQL_Table1_Connect_ID6,'>',@SQL_Table6_SourceValidFrom,'<',@SQL_Table6_SourceValidTo) else '' end
									,case when @Table7_Valid>0 then CONCAT(',07',@SQL_Table7_SourceString,'%',isnull(@SQL_Use_Table7_ID,0),':',@SQL_Table7_SourceJoinTyp,'#',@SQL_Table7_Connect_ID,'=',@SQL_Table1_Connect_ID7,'>',@SQL_Table7_SourceValidFrom,'<',@SQL_Table7_SourceValidTo) else '' end
									,case when @Table8_Valid>0 then CONCAT(',08',@SQL_Table8_SourceString,'%',isnull(@SQL_Use_Table8_ID,0),':',@SQL_Table8_SourceJoinTyp,'#',@SQL_Table8_Connect_ID,'=',@SQL_Table1_Connect_ID8,'>',@SQL_Table8_SourceValidFrom,'<',@SQL_Table8_SourceValidTo) else '' end
									,case when @Table9_Valid>0 then CONCAT(',09',@SQL_Table9_SourceString,'%',isnull(@SQL_Use_Table9_ID,0),':',@SQL_Table9_SourceJoinTyp,'#',@SQL_Table9_Connect_ID,'=',@SQL_Table1_Connect_ID9,'>',@SQL_Table9_SourceValidFrom,'<',@SQL_Table9_SourceValidTo) else '' end
									,case when @Table10_Valid>0 then CONCAT(',10',@SQL_Table10_SourceString,'%',isnull(@SQL_Use_Table10_ID,0),':',@SQL_Table10_SourceJoinTyp,'#',@SQL_Table10_Connect_ID,'=',@SQL_Table1_Connect_ID10,'>',@SQL_Table10_SourceValidFrom,'<',@SQL_Table10_SourceValidTo) else '' end
									,case when @Table11_Valid>0 then CONCAT(',11',@SQL_Table11_SourceString,'%',isnull(@SQL_Use_Table11_ID,0),':',@SQL_Table11_SourceJoinTyp,'#',@SQL_Table11_Connect_ID,'=',@SQL_Table1_Connect_ID11,'>',@SQL_Table11_SourceValidFrom,'<',@SQL_Table11_SourceValidTo) else '' end
									,case when @Table12_Valid>0 then CONCAT(',12',@SQL_Table12_SourceString,'%',isnull(@SQL_Use_Table12_ID,0),':',@SQL_Table12_SourceJoinTyp,'#',@SQL_Table12_Connect_ID,'=',@SQL_Table1_Connect_ID12,'>',@SQL_Table12_SourceValidFrom,'<',@SQL_Table12_SourceValidTo) else '' end
									,case when @Table13_Valid>0 then CONCAT(',13',@SQL_Table13_SourceString,'%',isnull(@SQL_Use_Table13_ID,0),':',@SQL_Table13_SourceJoinTyp,'#',@SQL_Table13_Connect_ID,'=',@SQL_Table1_Connect_ID13,'>',@SQL_Table13_SourceValidFrom,'<',@SQL_Table13_SourceValidTo) else '' end
									,case when @Table14_Valid>0 then CONCAT(',14',@SQL_Table14_SourceString,'%',isnull(@SQL_Use_Table14_ID,0),':',@SQL_Table14_SourceJoinTyp,'#',@SQL_Table14_Connect_ID,'=',@SQL_Table1_Connect_ID14,'>',@SQL_Table14_SourceValidFrom,'<',@SQL_Table14_SourceValidTo) else '' end
									,case when @Table15_Valid>0 then CONCAT(',15',@SQL_Table15_SourceString,'%',isnull(@SQL_Use_Table15_ID,0),':',@SQL_Table15_SourceJoinTyp,'#',@SQL_Table15_Connect_ID,'=',@SQL_Table1_Connect_ID15,'>',@SQL_Table15_SourceValidFrom,'<',@SQL_Table15_SourceValidTo) else '' end
									),'|x|',''),''', '','')
							where len(value)>3
							)
							SELECT @Liste_TableString=COALESCE(@Liste_TableString+N'','', N'''') + '''' + Spalte
							from Aufteilung t1
							order by Position
							;
						')

	EXEC sp_EXECutesql @SQL, N'@Liste_TableString nvarchar(max) OUT', @Liste_TableString OUT;
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

XP30:
	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='XP30'
	SET @Table_Status_LastChangeOnDate=Null
	SET @LastUpdate=Null
	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	SET @StepText=Concat('','@LastChangeOnDate der Dimensionstabelle [',@SQL_Table1_SourceString,'] suchen und als @Table_Status_LastChangeOnDate speichern.')
	SET @SQL=Concat('
					SET @Table_Status_LastChangeOnDate=isnull((Select Distinct LastChangeOnDate from ',@SQL_TableRelationTreeString,' where TargetObjectID=',OBJECT_ID(@SQL_Table1_SourceString,'U'),'),'''')			
					SET @LastUpdate=isnull((Select max(TargetUpdate) from ',@SQL_TableRelationTreeString,' where TargetObjectID=',OBJECT_ID(@SQL_Table1_SourceString,'U'),'),'''')		
					')

	EXEC sp_EXECutesql @SQL, N'@Table_Status_LastChangeOnDate int OUT, @LastUpdate DateTime2 OUT', @Table_Status_LastChangeOnDate OUT, @LastUpdate OUT;
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

	Print concat('
	@Table_Status_LastChangeOnDate	=',@Table_Status_LastChangeOnDate,'
	@LastUpdate						=',convert(nvarchar, @LastUpdate, 113))

XP35:
	If @Ladeverfahren='D' 
		begin
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
			SET @StepPraefix='XP35'
			SET @StepText= Concat('','Start: Erstelle Deltatab [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_1] aufbauen.')
			Set @SQL=concat('
					Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_DeltaTab

					Select distinct ',replace(@SQL_Table1_ID,'|x|',''),'
					into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_DeltaTab
					from 
						(
							Select ',replace(@SQL_Table1_ID,'|x|',''),'
							from ',@SQL_Table1_SourceString,'_Delta
							',case when @Table2_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table2_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID2,'|x|','')) 
								   else '' end,'
							',case when @Table3_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table3_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID3,'|x|','')) 
								   else '' end,'
							',case when @Table4_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table4_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID4,'|x|','')) 
								   else '' end,'
							',case when @Table5_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table5_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID5,'|x|','')) 
								   else '' end)

			Set @SQL1=concat(case when @Table6_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table6_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID6,'|x|','')) 
								   else '' end,'
							',case when @Table7_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table7_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID7,'|x|','')) 
								   else '' end,'
							',case when @Table8_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table8_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID8,'|x|','')) 
								   else '' end,'
							',case when @Table9_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table9_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID9,'|x|','')) 
								   else '' end,'
							',case when @Table10_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table10_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID10,'|x|','')) 
								   else '' end,'
							',case when @Table11_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table11_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID11,'|x|','')) 
								   else '' end,'
							',case when @Table12_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table12_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID12,'|x|','')) 
								   else '' end,'
							',case when @Table13_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table13_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID13,'|x|','')) 
								   else '' end,'
							',case when @Table14_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table14_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID14,'|x|','')) 
								   else '' end,'
							',case when @Table15_Valid>0 then concat('
										Union
										Select t0.',replace(@SQL_Table1_ID,'|x|',''),'
										from ',@SQL_TableTargetString,' t0 
										join ',@SQL_Table15_SourceString,'_DELTA t2 On t2.RowID=t0.',replace(@SQL_TableTargetRowID15,'|x|','')) 
								   else '' end,'
						) t1

					CREATE INDEX xTableID ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_DeltaTab (',replace(@SQL_Table1_ID,'|x|',''),' ASC)
					')

			EXEC(@SQL+@SQL1+@SQL2+@SQL3);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke	

		end

XP40:

	Print concat('
	####################################################################################
	Tabelle [',@SQL_Table1_SourceString,'] 
	Erforderliche Aktualisierungzeit: ',convert(nvarchar, @MaxDelayTimestamp, 113),'
	Letzte Aktualisierung: ',convert(nvarchar, @LastUpdate, 113),'
	Zeitpunkt: ',convert(nvarchar, getdate(), 113),'
	')

	If @LastUpdate<@MaxDelayTimestamp or @LastUpdate is null
		Begin
			Print concat('
			Start: Procedure zur Aktualisierung der Tabelle [',@SQL_Table1_SourceString,']!
			####################################################################################
			')

			SET @SQL = cast(OBJECT_ID(@SQL_Table1_SourceString,'U') as varchar(50))
			Execute dbo.procstarter @TargetObjectID=@SQL, @Ladeverfahren=@Ladeverfahren
			Print concat('
			####################################################################################
			Ende: ',convert(nvarchar, getdate(), 113),'
			####################################################################################
			')
			SET @SQL=''
		end
	else
		begin
			Print concat('','
			Keine Aktualisierung erforderlich!!!
			####################################################################################
			')		
		end 

	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='XP40'
	SET @StepText= Concat('','Start: Initiale Dimensionstabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_1] aufbauen.')
	Set @SQL=concat('
		Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG
	
		Select Distinct
			',replace(@SQL_Table1_SourceRowID,'|x|','t1.'),' as TableRowID1
			,t1.SchluesselID
			,',replace(@SQL_Table1_SourceRowID,'|x|','t1.'),' as ',replace(@SQL_TableTargetRowID1,'|x|',''),'	--Zeilennummer (RowID) der Dimensionstabelle
			,',replace(@Liste_ConnectingFields,'|x|','t1.'),'													--Liste aller Verbindungsfelder (ConnectingFields)
			',Trim(replace(@SQL_Table1_SourceFields,'|x|','t1.')),'												--Liste aller Felder, die mitgeführt werden müssen, weill Sie später gebraucht werden
			,',case when @LastChangeOnDate=1 then concat('cast(',replace(@SQL_Table1_SourceValidFrom,'|x|','t1.'),' as date)')
					else concat('cast(',replace(@SQL_Table1_SourceValidFrom,'|x|','t1.'),' as DateTime2)')
					end,' as Zeitstempel_von1
			,',case when @LastChangeOnDate=1 and @Table_Status_LastChangeOnDate=0 then concat('dateadd(d,-1,cast(',replace(@SQL_Table1_SourceValidTo,'|x|','t1.'),' as date))')
					when @LastChangeOnDate=1 and @Table_Status_LastChangeOnDate=1 then concat('cast(',replace(@SQL_Table1_SourceValidTo,'|x|','t1.'),' as date)')
					when @LastChangeOnDate=0 and @Table_Status_LastChangeOnDate=1 then concat('dateadd(s,-1,cast(dateadd(d,1,cast(',replace(@SQL_TableTargetValidTo,'|x|','t2.'),' as date)) as DateTime2))')
					else concat('cast(',replace(@SQL_Table1_SourceValidTo,'|x|','t1.'),' as DateTime2)')
			   end,' as Zeitstempel_bis1
		into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG
		from ',@SQL_Table1_SourceString,'  t1
		', case when @Ladeverfahren='D' and charindex(upper('_Delta'),upper(@SQL_Table1_SourceString))=0 then concat('join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_DeltaTab t99 on t1.',replace(@SQL_Table1_ID,'|x|',''),'=t99.',replace(@SQL_Table1_ID,'|x|',''),'') else '' end,'  
		',replace(@SQL_Table1_SourceJoin,'|x|','t1.'),' 
		', case when @LastChangeOnDate=1 then ' where t1.LastChangeOnDate=1' else ' where 1=1 ' end ,'
		', case when len(@SQL_Table1_SourceWhere) >3 then concat('and ',replace(@SQL_Table1_SourceWhere,'|x|','t1.')) else '' end ,'
		')

	EXEC(@SQL+@SQL1+@SQL2+@SQL3);
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke																	

	SET @ValidLoop=1
	SET @Loop=1
	SET @LoopIndex=0
	SET @Schleifenende=0

	Print '@Liste_TableString = '+ @Liste_TableString
	Print 'Starte Schleife...'

	While (CHARINDEX(',',@Liste_TableString+',',@LoopIndex)>0 or (@Loop=1 and LEN(@Liste_TableString)>3)) --and @Loop<12
		Begin

			SET @SQL_Connect=NULL; SET @SQL_ConnectSourceString=NULL; SET @SQL_ConnectID_Dim=NULL; SET @SQL_ConnectTableID=NULL; SET @UseConnectTabelID=0; SET @SQL_SourceJoinTyp=NULL; SET @SQL_ConnectID_Fak=NULL; 
			SET @SQL_ConnectValidFrom=NULL; SET @SQL_ConnectValidTo=NULL; SET @SQL_SourceWhere=NULL; SET @SQL_SourceFields=NULL; SET @SQL_CaseWhenRowID=NULL; SET @SQL_TableTargetRowID=NULL;

			if CHARINDEX(',',@Liste_TableString+',',@LoopIndex)>0
				SET @SQL_Connect=SUBSTRING(@Liste_TableString,@LoopIndex,CHARINDEX(',',@Liste_TableString+',',@LoopIndex)-@LoopIndex)
			else
				SET @SQL_Connect=@Liste_TableString
			Print concat('@SQL_Connect: ', @SQL_Connect)

			SET @Liste_Index = left(@SQL_Connect,2)
			SET @SQL_Connect= substring(@SQL_Connect,3,8000)
			Print @Liste_Index

			SET @LoopIndex = CHARINDEX(',',@Liste_TableString+',',@LoopIndex)+1
			Print concat('@LoopIndex: ', @LoopIndex)

			SET @SQL_ConnectSourceString=left(@SQL_Connect,CHARINDEX('%',@SQL_Connect,1)-1)
			Print concat('@SQL_ConnectSourceString: ', @SQL_ConnectSourceString) 

			SET @SQL_ConnectID_Dim	='|x|'+substring(@SQL_Connect, CHARINDEX('=',@SQL_Connect)+1,CHARINDEX('>',@SQL_Connect)-CHARINDEX('=',@SQL_Connect)-1)
			Print concat('@SQL_ConnectID_Dim: ', @SQL_ConnectID_Dim) 

			SET @UseConnectTabelID	=isnull(substring(@SQL_Connect, CHARINDEX('%',@SQL_Connect)+1,CHARINDEX(':',@SQL_Connect)-CHARINDEX('%',@SQL_Connect)-1),0)
			Print concat('@UseConnectTabelID: ', @UseConnectTabelID) 
			if @UseConnectTabelID not in (0,1)
				SET @UseConnectTabelID=1
			Print concat('@UseConnectTabelID neu: ', @UseConnectTabelID) 

			SET @SQL_SourceJoinTyp	=substring(@SQL_Connect, CHARINDEX(':',@SQL_Connect)+1,CHARINDEX('#',@SQL_Connect)-CHARINDEX(':',@SQL_Connect)-1)
			Print concat('@SQL_SourceJoinTyp: ', @SQL_SourceJoinTyp) 

			SET @SQL_ConnectID_Fak	='|x|'+substring(@SQL_Connect, CHARINDEX('#',@SQL_Connect)+1,CHARINDEX('=',@SQL_Connect)-CHARINDEX('#',@SQL_Connect)-1)
			Print concat('@SQL_ConnectID_Fak: ', @SQL_ConnectID_Fak) 

			SET @SQL_ConnectValidFrom	='|x|'+substring(@SQL_Connect, CHARINDEX('>',@SQL_Connect)+1,CHARINDEX('<',@SQL_Connect)-CHARINDEX('>',@SQL_Connect)-1)
			Print concat('@SQL_ConnectValidFrom: ', @SQL_ConnectValidFrom) 

			SET @SQL_ConnectValidTo		='|x|'+substring(@SQL_Connect, CHARINDEX('<',@SQL_Connect)+1,100)
			Print concat('@SQL_ConnectValidTo: ', @SQL_ConnectValidTo) 

			if LEN(@SQL_Connect)>3 and LEN(@SQL_ConnectID_Dim)>3 and LEN(@SQL_ConnectID_Fak)>3 and LEN(@SQL_ConnectSourceString)>3 
				Begin
					
					SET @SQL_SourceWhere=concat(
										case when len(@SQL_Table2_SourceWhere)>3 and @Liste_Index='02' then concat(' (',replace(@SQL_Table2_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table3_SourceWhere)>3 and @Liste_Index='03' then concat(' (',replace(@SQL_Table3_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table4_SourceWhere)>3 and @Liste_Index='04' then concat(' (',replace(@SQL_Table4_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table5_SourceWhere)>3 and @Liste_Index='05' then concat(' (',replace(@SQL_Table5_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table6_SourceWhere)>3 and @Liste_Index='06' then concat(' (',replace(@SQL_Table6_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table7_SourceWhere)>3 and @Liste_Index='07' then concat(' (',replace(@SQL_Table7_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table8_SourceWhere)>3 and @Liste_Index='08' then concat(' (',replace(@SQL_Table8_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table9_SourceWhere)>3 and @Liste_Index='09' then concat(' (',replace(@SQL_Table9_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table10_SourceWhere)>3 and @Liste_Index='10' then concat(' (',replace(@SQL_Table10_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table11_SourceWhere)>3 and @Liste_Index='11' then concat(' (',replace(@SQL_Table11_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table12_SourceWhere)>3 and @Liste_Index='12' then concat(' (',replace(@SQL_Table12_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table13_SourceWhere)>3 and @Liste_Index='13' then concat(' (',replace(@SQL_Table13_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table14_SourceWhere)>3 and @Liste_Index='14' then concat(' (',replace(@SQL_Table14_SourceWhere,'|x|','|x|'),')') else '' end
										,case when len(@SQL_Table15_SourceWhere)>3 and @Liste_Index='15' then concat(' (',replace(@SQL_Table15_SourceWhere,'|x|','|x|'),')') else '' end
										);

					SET @SQL_SourceWhere=Trim(REPLACE(REPLACE(REPLACE(@SQL_SourceWhere, CHAR(9), ''), CHAR(10), ''), CHAR(13), ''))
					Print '@SQL_SourceWhere: '+@SQL_SourceWhere

					SET @SQL_TableID=CONCAT(
							  case when @Table2_Valid>0 and len(@SQL_Table2_ID)>2 and @Liste_Index='02' then @SQL_Table2_ID else '' end,'
							',case when @Table3_Valid>0 and len(@SQL_Table3_ID)>2 and @Liste_Index='03' then @SQL_Table3_ID else '' end,'
							',case when @Table4_Valid>0 and len(@SQL_Table4_ID)>2 and @Liste_Index='04' then @SQL_Table4_ID else '' end,'
							',case when @Table5_Valid>0 and len(@SQL_Table5_ID)>2 and @Liste_Index='05' then @SQL_Table5_ID else '' end,'
							',case when @Table6_Valid>0 and len(@SQL_Table6_ID)>2 and @Liste_Index='06' then @SQL_Table6_ID else '' end,'
							',case when @Table7_Valid>0 and len(@SQL_Table7_ID)>2 and @Liste_Index='07' then @SQL_Table7_ID else '' end,'
							',case when @Table8_Valid>0 and len(@SQL_Table8_ID)>2 and @Liste_Index='08' then @SQL_Table8_ID else '' end,'
							',case when @Table9_Valid>0 and len(@SQL_Table9_ID)>2 and @Liste_Index='09' then @SQL_Table9_ID else '' end,'
							',case when @Table10_Valid>0 and len(@SQL_Table10_ID)>2 and @Liste_Index='10' then @SQL_Table10_ID else '' end,'
							',case when @Table11_Valid>0 and len(@SQL_Table11_ID)>2 and @Liste_Index='11' then @SQL_Table11_ID else '' end,'
							',case when @Table12_Valid>0 and len(@SQL_Table12_ID)>2 and @Liste_Index='12' then @SQL_Table12_ID else '' end,'
							',case when @Table13_Valid>0 and len(@SQL_Table13_ID)>2 and @Liste_Index='13' then @SQL_Table13_ID else '' end,'
							',case when @Table14_Valid>0 and len(@SQL_Table14_ID)>2 and @Liste_Index='14' then @SQL_Table14_ID else '' end,'
							',case when @Table15_Valid>0 and len(@SQL_Table15_ID)>2 and @Liste_Index='15' then @SQL_Table15_ID else '' end,'
					')

					SET @SQL_TableID='|x|'+Replace(Trim(REPLACE(REPLACE(REPLACE(@SQL_TableID, CHAR(9), ''), CHAR(10), ''), CHAR(13), '')),'|x|','')
					Print '@SQL_TableID: '+@SQL_TableID

					SET @SQL_TableTargetRowID=CONCAT(
							  case when @Table2_Valid>0 and len(@SQL_TableTargetRowID2)>2 and @Liste_Index='02' then @SQL_TableTargetRowID2 else '' end,'
							',case when @Table3_Valid>0 and len(@SQL_TableTargetRowID3)>2 and @Liste_Index='03' then @SQL_TableTargetRowID3 else '' end,'
							',case when @Table4_Valid>0 and len(@SQL_TableTargetRowID4)>2 and @Liste_Index='04' then @SQL_TableTargetRowID4 else '' end,'
							',case when @Table5_Valid>0 and len(@SQL_TableTargetRowID5)>2 and @Liste_Index='05' then @SQL_TableTargetRowID5 else '' end,'
							',case when @Table6_Valid>0 and len(@SQL_TableTargetRowID6)>2 and @Liste_Index='06' then @SQL_TableTargetRowID6 else '' end,'
							',case when @Table7_Valid>0 and len(@SQL_TableTargetRowID7)>2 and @Liste_Index='07' then @SQL_TableTargetRowID7 else '' end,'
							',case when @Table8_Valid>0 and len(@SQL_TableTargetRowID8)>2 and @Liste_Index='08' then @SQL_TableTargetRowID8 else '' end,'
							',case when @Table9_Valid>0 and len(@SQL_TableTargetRowID9)>2 and @Liste_Index='09' then @SQL_TableTargetRowID9 else '' end,'
							',case when @Table10_Valid>0 and len(@SQL_TableTargetRowID10)>2 and @Liste_Index='10' then @SQL_TableTargetRowID10 else '' end,'
							',case when @Table11_Valid>0 and len(@SQL_TableTargetRowID11)>2 and @Liste_Index='11' then @SQL_TableTargetRowID11 else '' end,'
							',case when @Table12_Valid>0 and len(@SQL_TableTargetRowID12)>2 and @Liste_Index='12' then @SQL_TableTargetRowID12 else '' end,'
							',case when @Table13_Valid>0 and len(@SQL_TableTargetRowID13)>2 and @Liste_Index='13' then @SQL_TableTargetRowID13 else '' end,'
							',case when @Table14_Valid>0 and len(@SQL_TableTargetRowID14)>2 and @Liste_Index='14' then @SQL_TableTargetRowID14 else '' end,'
							',case when @Table15_Valid>0 and len(@SQL_TableTargetRowID15)>2 and @Liste_Index='15' then @SQL_TableTargetRowID15 else '' end,'
					')

					SET @SQL_TableTargetRowID=Trim(REPLACE(REPLACE(REPLACE(@SQL_TableTargetRowID, CHAR(9), ''), CHAR(10), ''), CHAR(13), ''))
					Print '@SQL_TableTargetRowID: '+@SQL_TableTargetRowID

					SET @SQL_TableSourceRowID=CONCAT(
							  case when @Table2_Valid>0 and len(@SQL_Table2_SourceRowID)>2 and @Liste_Index='02' then @SQL_Table2_SourceRowID else '' end,'
							',case when @Table3_Valid>0 and len(@SQL_Table3_SourceRowID)>2 and @Liste_Index='03' then @SQL_Table3_SourceRowID else '' end,'
							',case when @Table4_Valid>0 and len(@SQL_Table4_SourceRowID)>2 and @Liste_Index='04' then @SQL_Table4_SourceRowID else '' end,'
							',case when @Table5_Valid>0 and len(@SQL_Table5_SourceRowID)>2 and @Liste_Index='05' then @SQL_Table5_SourceRowID else '' end,'
							',case when @Table6_Valid>0 and len(@SQL_Table6_SourceRowID)>2 and @Liste_Index='06' then @SQL_Table6_SourceRowID else '' end,'
							',case when @Table7_Valid>0 and len(@SQL_Table7_SourceRowID)>2 and @Liste_Index='07' then @SQL_Table7_SourceRowID else '' end,'
							',case when @Table8_Valid>0 and len(@SQL_Table8_SourceRowID)>2 and @Liste_Index='08' then @SQL_Table8_SourceRowID else '' end,'
							',case when @Table9_Valid>0 and len(@SQL_Table9_SourceRowID)>2 and @Liste_Index='09' then @SQL_Table9_SourceRowID else '' end,'
							',case when @Table10_Valid>0 and len(@SQL_Table10_SourceRowID)>2 and @Liste_Index='10' then @SQL_Table10_SourceRowID else '' end,'
							',case when @Table11_Valid>0 and len(@SQL_Table11_SourceRowID)>2 and @Liste_Index='11' then @SQL_Table11_SourceRowID else '' end,'
							',case when @Table12_Valid>0 and len(@SQL_Table12_SourceRowID)>2 and @Liste_Index='12' then @SQL_Table12_SourceRowID else '' end,'
							',case when @Table13_Valid>0 and len(@SQL_Table13_SourceRowID)>2 and @Liste_Index='13' then @SQL_Table13_SourceRowID else '' end,'
							',case when @Table14_Valid>0 and len(@SQL_Table14_SourceRowID)>2 and @Liste_Index='14' then @SQL_Table14_SourceRowID else '' end,'
							',case when @Table15_Valid>0 and len(@SQL_Table15_SourceRowID)>2 and @Liste_Index='15' then @SQL_Table15_SourceRowID else '' end,'
					')

					SET @SQL_TableSourceRowID=Trim(REPLACE(REPLACE(REPLACE(@SQL_TableSourceRowID, CHAR(9), ''), CHAR(10), ''), CHAR(13), ''))
					Print '@SQL_TableSourceRowID: '+@SQL_TableSourceRowID

					if len(trim(@SQL_SourceWhere))>3
						SET @SQL_CaseWhenRowID=concat('case when ',@SQL_SourceWhere,' then |x|',replace(@SQL_TableSourceRowID,'|x|',''),' else Null end as ',replace(@SQL_TableTargetRowID,'|x|',''))
					else
						SET @SQL_CaseWhenRowID=concat('|x|',replace(@SQL_TableSourceRowID,'|x|',''),' as ',replace(@SQL_TableTargetRowID,'|x|',''))
					
					Print '@SQL_CaseWhenRowID: '+@SQL_CaseWhenRowID

					SET @SQL_SourceFields=concat(
										 case when @Table2_Valid>0 and len(@SQL_Table2_SourceFields)>2 and @Liste_Index='02' then concat(',',@SQL_Table2_SourceFields) else '' end
										,case when @Table3_Valid>0 and len(@SQL_Table3_SourceFields)>2 and @Liste_Index='03' then concat(',',@SQL_Table3_SourceFields) else '' end
										,case when @Table4_Valid>0 and len(@SQL_Table4_SourceFields)>2 and @Liste_Index='04' then concat(',',@SQL_Table4_SourceFields) else '' end
										,case when @Table5_Valid>0 and len(@SQL_Table5_SourceFields)>2 and @Liste_Index='05' then concat(',',@SQL_Table5_SourceFields) else '' end
										,case when @Table6_Valid>0 and len(@SQL_Table6_SourceFields)>2 and @Liste_Index='06' then concat(',',@SQL_Table6_SourceFields) else '' end
										,case when @Table7_Valid>0 and len(@SQL_Table7_SourceFields)>2 and @Liste_Index='07' then concat(',',@SQL_Table7_SourceFields) else '' end
										,case when @Table8_Valid>0 and len(@SQL_Table8_SourceFields)>2 and @Liste_Index='08' then concat(',',@SQL_Table8_SourceFields) else '' end
										,case when @Table9_Valid>0 and len(@SQL_Table9_SourceFields)>2 and @Liste_Index='09' then concat(',',@SQL_Table9_SourceFields) else '' end
										,case when @Table10_Valid>0 and len(@SQL_Table10_SourceFields)>2 and @Liste_Index='10' then concat(',',@SQL_Table10_SourceFields) else '' end
										,case when @Table11_Valid>0 and len(@SQL_Table11_SourceFields)>2 and @Liste_Index='11' then concat(',',@SQL_Table11_SourceFields) else '' end
										,case when @Table12_Valid>0 and len(@SQL_Table12_SourceFields)>2 and @Liste_Index='12' then concat(',',@SQL_Table12_SourceFields) else '' end
										,case when @Table13_Valid>0 and len(@SQL_Table13_SourceFields)>2 and @Liste_Index='13' then concat(',',@SQL_Table13_SourceFields) else '' end
										,case when @Table14_Valid>0 and len(@SQL_Table14_SourceFields)>2 and @Liste_Index='14' then concat(',',@SQL_Table14_SourceFields) else '' end
										,case when @Table15_Valid>0 and len(@SQL_Table15_SourceFields)>2 and @Liste_Index='15' then concat(',',@SQL_Table15_SourceFields) else '' end
										);

					SET @SQL_SourceFields=Trim(REPLACE(REPLACE(REPLACE(@SQL_SourceFields, CHAR(9), ''), CHAR(10), ''), CHAR(13), ''))
					if len(@SQL_SourceFields)>3
						SET @SQL_SourceFields=replace(replace(@SQL_SourceFields,'|x|',''),',',',|x|')
				
					Print '@SQL_SourceFields: '+@SQL_SourceFields

XP50:					
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @Liste_ColumnsInTableORG=Null
					SET @StepPraefix=concat('XP50-',@Loop)
					SET @StepText=Concat('','Erstellt die @Liste_ColumnsInTableORG mit allen tatsächlich verfügbaren Spalten in der Dimensionstabelle [',@SQL_TableTargetName,'_TEMP',@TEMPPraefix,'_ORG]')
					SET @SQL=Concat('SELECT @Liste_ColumnsInTableORG=COALESCE(@Liste_ColumnsInTableORG+N'','', N'''') + ''|x|'' + t1.Spalte
										from (	
											SELECT Distinct c.name as Spalte, typ.name as Spaltentyp, c.max_length as Spaltenlaenge
											from ',@SQL_TableTargetDB,'.sys.columns c
												join ',@SQL_TableTargetDB,'.sys.tables tab ON c.object_id=tab.object_id
												join ',@SQL_TableTargetDB,'.sys.types typ ON c.user_type_id=typ.user_type_id
											WHERE tab.object_id = object_id(''',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG'',''U'')
												and c.name <> ''Zeitstempel_von1'' 
												and c.name <> ''Zeitstempel_bis1''  
												and c.name <> ''SchluesselID''  
												and c.name <> ''SchluesselID2''  
												and c.name <> ''TableRowID1''
												and c.name <> ''ConnectTableID''
											) t1
										order by t1.Spalte')

					EXEC sp_EXECutesql @SQL, N'@Liste_ColumnsInTableORG nvarchar(max) OUT', @Liste_ColumnsInTableORG OUT;
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

XP60:

					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @SQL_ConnectTableID=Null
					SET @LastUpdate=Null
					SET @SQL_ConnectTableID=Null
					SET @StepPraefix=concat('XP60-',@Loop)
					SET @StepText=Concat('','ID der Tabelle [',@SQL_ConnectSourceString,'] suchen und als @SQL_ConnectTableID speichern.')
					SET @SQL=Concat('
									SET @SQL_ConnectTableID=''|x|''+isnull((Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_ConnectSourceString,'U')),'),'''')	
									SET @Table_Status_LastChangeOnDate=isnull((Select Distinct LastChangeOnDate from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_ConnectSourceString,'U')),'),'''')		
									SET @LastUpdate=isnull((Select Max(TargetUpdate) from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_ConnectSourceString,'U')),'),'''')		
									')
									--> wenn SQL_ConnectTableID is null... dann Procedure neu Starten!

					EXEC sp_EXECutesql @SQL, N'@Table_Status_LastChangeOnDate int OUT, @SQL_ConnectTableID varchar(200) OUT, @LastUpdate DateTime2 OUT', @Table_Status_LastChangeOnDate OUT, @SQL_ConnectTableID OUT, @LastUpdate OUT;
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

					Print concat('
					####################################################################################
					Tabelle [',@SQL_ConnectSourceString,'] 
					Erforderliche Aktualisierungzeit: ',convert(nvarchar, @MaxDelayTimestamp, 113),'
					Letzte Aktualisierung: ',convert(nvarchar, @LastUpdate, 113),'
					Zeitpunkt: ',convert(nvarchar, getdate(), 113),'
					')

					If @LastUpdate<@MaxDelayTimestamp or @LastUpdate is null
						Begin
							Print concat('
							Start: Procedure zur Aktualisierung der Tabelle [',@SQL_ConnectSourceString,']!
							####################################################################################
							')

							SET @SQL = cast(OBJECT_ID(@SQL_ConnectSourceString,'U') as varchar(50))
							Execute dbo.procstarter @TargetObjectID=@SQL, @Ladeverfahren=@Ladeverfahren
							Print concat('
							####################################################################################
							Ende: ',convert(nvarchar, getdate(), 113),'
							####################################################################################
							')
							SET @SQL=''
						end 
					else
						begin
							Print concat('','
							Keine Aktualisierung erforderlich!!!
							####################################################################################
							')		
						end 
XP70:
					
					if len(trim(@SQL_TableID))>3 and upper(trim(replace(@SQL_TableID,'|x|','')))<>upper('SchluesselID')
						SET @SQL_ConnectTableID=@SQL_TableID

					if len(trim(@SQL_ConnectTableID))>3 and upper(trim(replace(@SQL_ConnectTableID,'|x|','')))<>upper('SchluesselID') and @UseConnectTabelID<>0
						begin
							SET @UseConnectTabelID=2
							SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
							SET @StepPraefix=concat('XP70-',@Loop)
							SET @StepText=Concat('','SchluesselID wird für [',@SQL_ConnectTableID,'] in Tabelle [',@SQL_ConnectSourceString,'] erstellt und in Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Key0] gespeichern.')

							SET @SQL=Concat('
							Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Key0;

							Select ',replace(@SQL_ConnectTableID,'|x|',''),', Row_Number() over (order by ',replace(@SQL_ConnectTableID,'|x|',''),') as SchluesselID2
							into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Key0
							from (Select distinct ',replace(@SQL_ConnectTableID,'|x|','t1.'),' 
									from ',@SQL_ConnectSourceString,' t1
									join (Select distinct ',replace(@SQL_ConnectID_Dim,'|x|',''),' 
									from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG
									where ',replace(@SQL_ConnectID_Dim,'|x|',''),' is not null
									) t2 on ',replace(@SQL_ConnectID_Dim,'|x|','t2.'),'=',replace(@SQL_ConnectID_Fak,'|x|','t1.'),' and ',replace(@SQL_ConnectID_Fak,'|x|','t1.'),' is not null
									where ',replace(@SQL_ConnectTableID,'|x|','t1.'),' is not null

									) t

							CREATE INDEX x',replace(@SQL_ConnectTableID,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Key0 (',replace(@SQL_ConnectTableID,'|x|',''),' ASC) 
							')

							EXEC(@SQL+@SQL1+@SQL2);
							SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
							EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

							if @Fehler>0
								goto Fehlermarke
						end

XP80:
					if @Schleifenende=0
						begin
							SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
							SET @StepPraefix=concat('XP80-',@Loop)
							SET @StepText=Concat('Index [xSchluesselID] für Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG] erstellen.')

							SET @SQL1=Concat('CREATE INDEX xSchluesselID ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (SchluesselID ASC, ',replace(@SQL_ConnectID_Dim,'|x|',''),')')
					
							EXEC(@SQL+@SQL1+@SQL2);
							SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
							EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

							if @Fehler>0
								goto Fehlermarke
						end
XP90:

					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix=concat('XP90-',@Loop)
					SET @StepText=Concat('','Faktentabelle [',@SQL_ConnectSourceString,'] filtern und in Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_0] speichern.')

					SET @SQL1=Concat('
								Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_0;

								Select  
									RowID as TableRowID2
									,t1.*
									,',replace(@SQL_ConnectID_Fak,'|x|','t1.'),' as VerknuepfungID
									,',case @UseConnectTabelID 
											when 1 then replace(@SQL_ConnectTableID,'|x|','t1.')
											when 2 then replace(@SQL_ConnectTableID,'|x|','t1.') 
											when 0 then '0' end,' as TableID2
									,',case when @LastChangeOnDate=1 
											then concat('cast(',replace(@SQL_TableTargetValidFrom,'|x|','t1.'),' as date)')
											else concat('cast(',replace(@SQL_TableTargetValidFrom,'|x|','t1.'),' as DateTime2)')
										end,' as Zeitstempel_von2
									,',case when @LastChangeOnDate=1 and @Table_Status_LastChangeOnDate=1 then concat('cast(',replace(@SQL_TableTargetValidTo,'|x|','t1.'),' as date)')
											when @LastChangeOnDate=1 and @Table_Status_LastChangeOnDate=0 then concat('
												case when year(',replace(@SQL_TableTargetValidTo,'|x|','t1.'),')=2099 or dateadd(d,-1,cast(',replace(@SQL_TableTargetValidTo,'|x|','t1.'),' as date)) < cast(',replace(@SQL_TableTargetValidFrom,'|x|','t1.'),' as date)
													 then cast(',replace(@SQL_TableTargetValidTo,'|x|','t1.'),' as date)
													 else dateadd(d,-1,cast(',replace(@SQL_TableTargetValidTo,'|x|','t1.'),' as date)) 
											     end')
											when @LastChangeOnDate=0 and @Table_Status_LastChangeOnDate=1 then concat('dateadd(s,-1,cast(dateadd(d,1,cast(',replace(@SQL_TableTargetValidTo,'|x|','t1.'),' as date)) as DateTime2))')
											else concat('cast(',replace(@SQL_TableTargetValidTo,'|x|','t1.'),' as DateTime2)')
										end,' as Zeitstempel_bis2
								into  ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_0
								')

					SET @SQL2=Concat('
								from ',@SQL_ConnectSourceString,' t1
									join (Select distinct ',replace(@SQL_ConnectID_Dim,'|x|',''),' 
									from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG
									where ',replace(@SQL_ConnectID_Dim,'|x|',''),' is not null
									) t2 on ',replace(@SQL_ConnectID_Dim,'|x|','t2.'),'=',replace(@SQL_ConnectID_Fak,'|x|','t1.'),' and ',replace(@SQL_ConnectID_Fak,'|x|','t1.'),' is not null
								where ',replace(@SQL_ConnectID_Fak,'|x|','t1.'),' is not null and len(trim(cast(',replace(@SQL_ConnectID_Fak,'|x|','t1.'),' as varchar(500))))>0
								', case when @LastChangeOnDate=1 then ' and t1.LastChangeOnDate=1' else '' end ,'
								')
					
					--ToDo xBase: Abfragen aller Spaltennamen in der ORG Tabelle und Prüfung, ob in @SQL_SourceWhere enthalten --> Gefahr von Dopplungen oder löschen aller xBase-Inhalte aus @SQL_SourceWhere --> Schwieriger

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

					if @RowCount=0
						begin
							Print concat('Keine Daten in der Spalte [',replace(@SQL_ConnectID_Dim,'|x|',''),'] enthalten! Weiter mit nächster Verbindung!')
							SET @SQL=concat('
										USE ',@SQL_TableTargetDB,'
										ALTER TABLE ',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_TEMP',@TEMPPraefix,'_ORG
										ADD ',replace(@SQL_TableTargetRowID,'|x|',''),' bigint NULL;
										')
							Print @SQL
							Exec(@SQL)
							SET @Schleifenende=1
							goto Schleifenende
						end
					else
						begin
							SET @Schleifenende=0
						end
XP100:
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix=concat('XP100-',@Loop)
					SET @StepText= Concat('Index [xVerknuepfungID] für Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_0] erstellen.')

					Set @SQL=concat('
					CREATE INDEX xVerknuepfungID ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_0 (VerknuepfungID ASC)
					')

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke	

XP110:
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix=concat('XP110-',@Loop)
					SET @StepText= Concat('Faktentabelle [',@SQL_ConnectSourceString,'] an die Dimensionstabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG] anbinden und in Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_1] speichern.')

					Set @SQL=concat('
					Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_1;

					Select Distinct
						 t1.TableRowID1
						,t2.TableRowID2
					    ,t1.SchluesselID
						,t1.',replace(@SQL_Table1_ID,'|x|',''),' as TableID1
						,',case when @UseConnectTabelID=0 then concat('t1.',replace(@SQL_Table1_ID,'|x|','')) else concat('isnull(cast(t2.TableID2 as varchar(500)),cast(t1.',replace(@SQL_Table1_ID,'|x|',''),' as varchar(500)))') end ,' as TableID2
					    ',replace(@SQL_SourceFields,'|x|','t2.'),'													--Neue Spalten aus der aktuellen Faktentabelle, die für eine spätere Verwendung hinzugefügt werden
						,',replace(@SQL_ConnectID_Dim,'|x|','t1.'),' as VerknuepfungID
						,',replace(replace(replace(@SQL_CaseWhenRowID,'|x|','t2.'),'|xBase|','t1.'),'''''',''),'	--RowID aus der aktuellen Faktentabelle
						,t1.Zeitstempel_von1
						,t1.Zeitstempel_bis1
						,case when t1.Zeitstempel_von1 > t2.Zeitstempel_von2 then t1.Zeitstempel_von1 else t2.Zeitstempel_von2 end as Zeitstempel_von2
						,case when t1.Zeitstempel_bis1 < t2.Zeitstempel_bis2 then t1.Zeitstempel_bis1 else t2.Zeitstempel_bis2 end as Zeitstempel_bis2
					into  ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_1
					from  ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG t1
					',@SQL_SourceJoinTyp,' join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_0 t2 on ',replace(@SQL_ConnectID_Dim,'|x|','t1.'),'=t2.VerknuepfungID
							and (t2.Zeitstempel_von2 between t1.Zeitstempel_von1 and t1.Zeitstempel_bis1
								or t2.Zeitstempel_bis2 between t1.Zeitstempel_von1 and t1.Zeitstempel_bis1
								or (t2.Zeitstempel_von2 < t1.Zeitstempel_von1 and t2.Zeitstempel_bis2 > t1.Zeitstempel_bis1))
							and ',replace(@SQL_ConnectID_Fak,'|x|','t2.'),' is not null and len(trim(cast(',replace(@SQL_ConnectID_Fak,'|x|','t2.'),' as varchar(500))))>0
							and ',replace(@SQL_ConnectID_Dim,'|x|','t1.'),' is not null and len(trim(cast(',replace(@SQL_ConnectID_Dim,'|x|','t1.'),' as varchar(500))))>0
					', case when len(trim(replace(@SQL_SourceWhere,'|x|',''))) >2 then concat(' and ',replace(replace(@SQL_SourceWhere,'|x|','t2.'),'|xBase|','t1.')) else '' end,'

					')

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke	
						
					--Irgendwann muss die Tabl1_ID ergänzt werden, wenn eine andere ID genutzt werden soll

XP120:
					If @UseConnectTabelID>0
						begin
							SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
							SET @StepPraefix=concat('XP120-',@Loop)
							SET @StepText= Concat('','Neue ID für Dimensions- und Faktentabelle ermitteln und in Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_2] speichern.')
							Set @SQL=concat('
							Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_key1;

							Select TableID1, TableID2, Row_Number() over (order by TableID1, TableID2) as SchluesselID_New
							into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_key1
							from (Select distinct TableID1, TableID2
								  from (Select distinct TableID1, isnull(TableID2,TableID1) as TableID2 from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_1
										union
										Select distinct TableID1, TableID1 as TableID2 from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_1
									   ) t1
								 ) t2
							') 

							EXEC(@SQL+@SQL1+@SQL2);
							SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
							EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

							if @Fehler>0
								goto Fehlermarke
						end
XP130:
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix=concat('XP130-',@Loop)
					SET @StepText= Concat('','Gemeinsame Zeiträume von Dimensions- und Faktentabelle aus Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_2] ermitteln und in Zeittabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_3] speichern.')
					Set @SQL=concat('
					Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_2;

					Select Distinct 
						t1.TableRowID1
						,isnull(t1.TableRowID2,0) as TableRowID2
						,t1.SchluesselID
						,isnull(t1.TableID2,0) as TableID2
						,',case when @UseConnectTabelID>0 then 't2.SchluesselID_New' else 't1.SchluesselID' end,' as SchluesselID_New
						,t1.VerknuepfungID
						,t1.Zeitstempel_von1
						,t1.Zeitstempel_bis1
						,t1.Zeitstempel_von2 
						,t1.Zeitstempel_bis2
						,case when t1.Zeitstempel_von2 between t1.Zeitstempel_von1 and t1.Zeitstempel_bis1 
							or t1.Zeitstempel_bis2 between t1.Zeitstempel_von1 and t1.Zeitstempel_bis1 then 1 else 0 end Zeitstempel_between
					into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_2
					from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_1 t1
						',case when @UseConnectTabelID>0
							   then concat(' join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_key1 t2 on t1.TableID1=t2.TableID1 and isnull(t1.TableID2,t1.TableID1)=isnull(t2.TableID2,t1.TableID1)')
							   else '' end,'
					')
				
					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke
XP140:
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @SQL_TempTableString=concat(@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_2')
					SET @StepPraefix=concat('XP140-',@Loop)
					SET @StepText= Concat('','Gemeinsame Zeiträume von Dimensions- und Faktentabelle aus Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_2] ermitteln und in Zeittabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_3] speichern.')
					Set @SQL=concat('
					Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_3;

					Select Distinct 
							SchluesselID_New, case when avg(KeyBis)=1 then dateadd(',case when @LastChangeOnDate=1 then 'day' else 'second' end,',-1,Zeitstempel) else Zeitstempel end as Zeitstempel
					into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_3
					from (
							Select SchluesselID_New, 0 as KeyBis, Zeitstempel_von1 as Zeitstempel from ',@SQL_TempTableString,' where year(Zeitstempel_von1) between 1990 and 2098 and Zeitstempel_between=1
							union
							Select SchluesselID_New, 1 as KeyBis, 
								case when dateadd(',case when @LastChangeOnDate=1 then 'day' else 'second' end,',1,Zeitstempel_bis1) > Zeitstempel_von1
									 then dateadd(',case when @LastChangeOnDate=1 then 'day' else 'second' end,',1,Zeitstempel_bis1)
									 else Zeitstempel_von1 end as Zeitstempel 
							from ',@SQL_TempTableString,' where year(Zeitstempel_bis1) between 1990 and 2098 and Zeitstempel_between=1
							union
							Select SchluesselID_New, 0 as KeyBis, Zeitstempel_von2 as Zeitstempel from ',@SQL_TempTableString,' where year(Zeitstempel_von2) between 1990 and 2098 and Zeitstempel_between=1
							union
							Select SchluesselID_New, 1 as KeyBis, 
								case when dateadd(',case when @LastChangeOnDate=1 then 'day' else 'second' end,',1,Zeitstempel_bis2) > Zeitstempel_von2
									 then dateadd(',case when @LastChangeOnDate=1 then 'day' else 'second' end,',1,Zeitstempel_bis2)
									 else Zeitstempel_von2 end as Zeitstempel 
							from ',@SQL_TempTableString,' where year(Zeitstempel_bis2) between 1990 and 2098 and Zeitstempel_between=1
							) t1

					where Zeitstempel is not null 
					group by SchluesselID_New, Zeitstempel

					')

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke																	
XP142:
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix=concat('XP142-',@Loop)
					SET @StepText= Concat('Index [xSchluesselID] für [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_3] erstellen.')
					SET @SQL=concat('
					CREATE INDEX xSchluesselID ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_3 (SchluesselID_New ASC)
					')
					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke	
XP144:
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix=concat('XP144-',@Loop)
					SET @StepText= Concat('Die RowID Informationen der Basistabelle in Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_4] speichern.')
					SET @SQL=concat('
					Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_4;

					Select
						t1.SchluesselID_New
						,t1.TableRowID1
						,0 as TableRowID2
						,t1.Zeitstempel_von1 
					into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_4
					from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_2 t1
						join (Select distinct SchluesselID_New from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_2) t2 on t1.SchluesselID_New=t2.SchluesselID_New
					where Zeitstempel_von2 is null
					')
					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke	
XP146:
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix=concat('XP146-',@Loop)
					SET @StepText= Concat('Neue RowID Kombinationen in die Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_4] einfügen.')
					SET @SQL=concat('
					Insert into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_4
					Select 
						t1.SchluesselID_New
						,isnull(t2.TableRowID1,t3.TableRowID1) as TableRowID1
						,isnull(t2.TableRowID2,0) as TableRowID2
						,t1.Zeitstempel as Zeitstempel_von1
					from  ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_3 t1
						left join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_2 t2 on t1.SchluesselID_New=t2.SchluesselID_New and t1.Zeitstempel between t2.Zeitstempel_von2 and t2.Zeitstempel_bis2
						left join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_2 t3 on t1.SchluesselID_New=t3.SchluesselID_New and t1.Zeitstempel between t3.Zeitstempel_von1 and t3.Zeitstempel_bis1
					where isnull(t2.TableRowID1,t3.TableRowID1) is not null
					')
					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke	
XP148:
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix=concat('XP148-',@Loop)
					SET @StepText= Concat('Neue RowID-Kombinationen und Zeiträume in Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_5] speichern.')
					SET @SQL=concat('
					Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_5;

					Select SchluesselID_New, TableRowID1, TableRowID2, Zeitstempel_von1
						   ,dateadd(',case when @LastChangeOnDate=1 then 'day' else 'second' end,',-1,isnull(lead(Zeitstempel_von1) over (partition by SchluesselID_New order by Zeitstempel_von1),cast(''1.1.2100'' as ',case when @LastChangeOnDate=1 then 'date' else 'DateTime2' end,'))) as Zeitstempel_bis1
					into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_5
					from (Select distinct SchluesselID_New, TableRowID1, TableRowID2, Zeitstempel_von1 from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_4) t
					')

					EXEC(@SQL+@SQL1);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

XP150:
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix=concat('XP150-',@Loop)
					SET @StepText= Concat('Index [xTableRowID1] und [xTableRowID2] für [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_4] erstellen.')
					SET @SQL=concat('
					
					CREATE INDEX xTableRowID1 ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_5 (TableRowID1 ASC)
					CREATE INDEX xTableRowID2 ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_5 (TableRowID2 ASC)

					')

					EXEC(@SQL+@SQL1);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

XP160:
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix=concat('XP160-',@Loop)
					SET @StepText= Concat('Die Dimensionstabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG] und Faktentabelle [',@SQL_ConnectSourceString,'] an Zeittabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_3] anspielen und in Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_6] speichern.')
					SET @SQL=concat('
					Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_6;

					Select Distinct
						',case when @UseConnectTabelID>0 then 't2.SchluesselID_New' else 't1.SchluesselID' end,' as SchluesselID
						,',replace(@Liste_ColumnsInTableORG,'|x|','t1.'),'											--Spalten aus der alten ORG-Tabelle
						',replace(@SQL_SourceFields,'|x|','t3.'),'													--Neue Spalten aus der aktuellen Faktentabelle, die für eine spätere Verwendung hinzugefügt werden
						,',replace(replace(replace(@SQL_CaseWhenRowID,'|x|','t3.'),'|xBase|','t1.'),'''''',''),'	--RowID aus der aktuellen Faktentabelle
						,isnull(t2.Zeitstempel_von1,t1.Zeitstempel_von1) as Zeitstempel_von1
						,case when t1.Zeitstempel_bis1 < isnull(t2.Zeitstempel_bis1,t1.Zeitstempel_bis1) then t1.Zeitstempel_bis1 else isnull(t2.Zeitstempel_bis1,t1.Zeitstempel_bis1) end as Zeitstempel_bis1
					into  ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_6
					from  ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG t1
						left join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_5 t2 on t1.TableRowID1=t2.TableRowID1 
						',@SQL_SourceJoinTyp,' join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_0 t3 on t2.TableRowID2=t3.TableRowID2
						',case when len(trim(@SQL_SourceWhere))>2 then concat(' and',replace(replace(replace(@SQL_SourceWhere,'|x|','t3.'),'|xBase|','t1.'),'''''','')) else '' end,'

					Delete ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_6
					where Zeitstempel_von1>Zeitstempel_bis1
					')

					EXEC(@SQL+@SQL1);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke																	

XP170:
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix=concat('XP170-',@Loop)
					SET @StepText= Concat('Die Dimensionstabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG] und Faktentabelle [',@SQL_ConnectSourceString,'] an Zeittabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_3] anspielen und in Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG] speichern.')
					SET @SQL=concat('
					if ',@Loop,'=99
						Select Top 50 ''_ORG_ALT'' as Tab, ',@Loop,' as Loop, * from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG 

					Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG;

					Select IDENTITY(BIGINT,1,1) as TableRowID1
						,SchluesselID
						
						,',replace(@Liste_ColumnsInTableORG,'|x|',''),'				--Spalten aus der alten ORG-Tabelle
						',replace(@SQL_SourceFields,'|x|',''),'						--Neue Spalten aus der aktuellen Faktentabelle, die für eine spätere Verwendung hinzugefügt werden
						,',replace(@SQL_TableTargetRowID,'|x|',''),'				--RowID aus der aktuellen Faktentabelle

						,Zeitstempel_von1
						,Zeitstempel_bis1
					into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG
					from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_6 t1

					if ',@Loop,' =99
						begin
							Select ''_0'' as Tab, ',@Loop,' as Loop, * from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_0 --where FallID=''10000010018045881'' 
							Select Top 50 ''_1'' as Tab, ',@Loop,' as Loop, * from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_1 
							Select Top 50 ''_2'' as Tab, ',@Loop,' as Loop, * from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_2 
							Select Top 50 ''_3'' as Tab, ',@Loop,' as Loop, * from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_3 
							Select Top 50 ''_4'' as Tab, ',@Loop,' as Loop, * from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_4 --where FallID=''10000010018045881'' 
							Select Top 50 ''_5'' as Tab, ',@Loop,' as Loop, * from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_5 --where FallID=''10000010018045881'' 
							Select Top 50 ''_6'' as Tab, ',@Loop,' as Loop, * from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_6 --where FallID=''10000010018045881'' 
							Select Top 50 ''_ORG_NEU'' as Tab, ',@Loop,' as Loop, * from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG
							Print ',@Loop,'
						end
					')


					EXEC(@SQL+@SQL1);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke	

					--Abbruch
					if @Loop=99
						goto Endmarke

					SET @ValidLoop=@Loop
				End
Schleifenende:				
				Set @Loop=@Loop+1
		end

XP180:
	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='XP180'
	SET @StepText=Concat('Erstellt die @Liste_ColumnsInTableORG mit allen tatsächlich verfügbaren Spalten aus der Ergebnistabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG] und fügt eine TRIM-Funktion hinzu.')
	SET @SQL=Concat('SELECT @Liste_ColumnsInTableORG=COALESCE(@Liste_ColumnsInTableORG+N'','', N'''') + case when CHARINDEX(''char'', t1.Spaltentyp)>0 then ''Trim(|x|'' + t1.Spalte + '')'' else ''|x|'' + t1.Spalte end + '' as '' + t1.Spalte
						from (
							SELECT c.name as Spalte, typ.name as Spaltentyp, c.max_length as Spaltenlaenge
							from ',@SQL_TableTargetDB,'.sys.columns c
								join ',@SQL_TableTargetDB,'.sys.tables tab ON c.object_id=tab.object_id
								join ',@SQL_TableTargetDB,'.sys.types typ ON c.user_type_id=typ.user_type_id
							WHERE tab.object_id = object_id(''',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG'',''U'')
									and c.name <> ''Zeitstempel_von1''  
									and c.name <> ''Zeitstempel_bis1''  
									and c.name <> ''SchluesselID''  
									and c.name <> ''TableRowID1''
									and c.name <> ''ConnectTableID''
									and c.name <> ''LastChangeOnDate''
							) t1 
						order by t1.Spalte')

	EXEC sp_EXECutesql @SQL, N'@Liste_ColumnsInTableORG nvarchar(max) OUT', @Liste_ColumnsInTableORG OUT;
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

XP190:
	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='XP190'
	SET @StepText= Concat('Index für alle RowIDs in [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG] erstellen')
	SET @SQL=concat('
		',case when @Table1_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID1,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID1,'|x|',''),' ASC);') else '' end,'
		',case when @Table2_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID2,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID2,'|x|',''),' ASC);') else '' end,'
		',case when @Table3_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID3,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID3,'|x|',''),' ASC);') else '' end,'
		',case when @Table4_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID4,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID4,'|x|',''),' ASC);') else '' end,'
		',case when @Table5_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID5,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID5,'|x|',''),' ASC);') else '' end,'
		',case when @Table6_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID6,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID6,'|x|',''),' ASC);') else '' end,'
		',case when @Table7_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID7,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID7,'|x|',''),' ASC);') else '' end,'
		',case when @Table8_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID8,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID8,'|x|',''),' ASC);') else '' end,'
		',case when @Table9_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID9,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID9,'|x|',''),' ASC);') else '' end,'
		',case when @Table10_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID10,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID10,'|x|',''),' ASC);') else '' end,'
		',case when @Table11_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID11,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID11,'|x|',''),' ASC);') else '' end,'
		',case when @Table12_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID12,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID12,'|x|',''),' ASC);') else '' end,'
		',case when @Table13_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID13,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID13,'|x|',''),' ASC);') else '' end,'
		',case when @Table14_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID14,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID14,'|x|',''),' ASC);') else '' end,'
		',case when @Table15_Valid>0 then concat('CREATE INDEX x',replace(@SQL_TableTargetRowID15,'|x|',''),' ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG (',replace(@SQL_TableTargetRowID15,'|x|',''),' ASC);') else '' end,'
		')

	EXEC(@SQL+@SQL1+@SQL2+@SQL3);
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

XP200:
	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='XP200'
	SET @StepText= Concat('Ergebnisstabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Test] erstellen')
	SET @SQL=concat('

		Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Test;

		Select 
			Top 0
			',@SQL_TableTargetDefinition1)
	SET @SQL1=@SQL_TableTargetDefinition2
	SET @SQL2=@SQL_TableTargetDefinition3
	SET @SQL3=concat('
		into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Test
		from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG t0
			',case when @Table1_Valid>0 then concat('left join ',@SQL_Table1_SourceString,' t1 on ',replace(@SQL_TableTargetRowID1,'|x|','t0.'),'=',replace(@SQL_Table1_SourceRowID,'|x|','t1.')) else '' end,'
			',case when @Table2_Valid>0 then concat('left join ',@SQL_Table2_SourceString,' t2 on ',replace(@SQL_TableTargetRowID2,'|x|','t0.'),'=',replace(@SQL_Table2_SourceRowID,'|x|','t2.')) else '' end,'
			',case when @Table3_Valid>0 then concat('left join ',@SQL_Table3_SourceString,' t3 on ',replace(@SQL_TableTargetRowID3,'|x|','t0.'),'=',replace(@SQL_Table3_SourceRowID,'|x|','t3.')) else '' end,'		
			',case when @Table4_Valid>0 then concat('left join ',@SQL_Table4_SourceString,' t4 on ',replace(@SQL_TableTargetRowID4,'|x|','t0.'),'=',replace(@SQL_Table4_SourceRowID,'|x|','t4.')) else '' end,'
			',case when @Table5_Valid>0 then concat('left join ',@SQL_Table5_SourceString,' t5 on ',replace(@SQL_TableTargetRowID5,'|x|','t0.'),'=',replace(@SQL_Table5_SourceRowID,'|x|','t5.')) else '' end,'
			',case when @Table6_Valid>0 then concat('left join ',@SQL_Table6_SourceString,' t6 on ',replace(@SQL_TableTargetRowID6,'|x|','t0.'),'=',replace(@SQL_Table6_SourceRowID,'|x|','t6.')) else '' end,'		
			',case when @Table7_Valid>0 then concat('left join ',@SQL_Table7_SourceString,' t7 on ',replace(@SQL_TableTargetRowID7,'|x|','t0.'),'=',replace(@SQL_Table7_SourceRowID,'|x|','t7.')) else '' end,'
			',case when @Table8_Valid>0 then concat('left join ',@SQL_Table8_SourceString,' t8 on ',replace(@SQL_TableTargetRowID8,'|x|','t0.'),'=',replace(@SQL_Table8_SourceRowID,'|x|','t8.')) else '' end,'
			',case when @Table9_Valid>0 then concat('left join ',@SQL_Table9_SourceString,' t9 on ',replace(@SQL_TableTargetRowID9,'|x|','t0.'),'=',replace(@SQL_Table9_SourceRowID,'|x|','t9.')) else '' end,'		
			',case when @Table10_Valid>0 then concat('left join ',@SQL_Table10_SourceString,' t10 on ',replace(@SQL_TableTargetRowID10,'|x|','t0.'),'=',replace(@SQL_Table10_SourceRowID,'|x|','t10.')) else '' end,'
			',case when @Table11_Valid>0 then concat('left join ',@SQL_Table11_SourceString,' t11 on ',replace(@SQL_TableTargetRowID11,'|x|','t0.'),'=',replace(@SQL_Table11_SourceRowID,'|x|','t11.')) else '' end,'
			',case when @Table12_Valid>0 then concat('left join ',@SQL_Table12_SourceString,' t12 on ',replace(@SQL_TableTargetRowID12,'|x|','t0.'),'=',replace(@SQL_Table12_SourceRowID,'|x|','t12.')) else '' end,'		
			',case when @Table13_Valid>0 then concat('left join ',@SQL_Table13_SourceString,' t13 on ',replace(@SQL_TableTargetRowID13,'|x|','t0.'),'=',replace(@SQL_Table13_SourceRowID,'|x|','t13.')) else '' end,'
			',case when @Table14_Valid>0 then concat('left join ',@SQL_Table14_SourceString,' t14 on ',replace(@SQL_TableTargetRowID14,'|x|','t0.'),'=',replace(@SQL_Table14_SourceRowID,'|x|','t14.')) else '' end,'
			',case when @Table15_Valid>0 then concat('left join ',@SQL_Table15_SourceString,' t15 on ',replace(@SQL_TableTargetRowID15,'|x|','t0.'),'=',replace(@SQL_Table15_SourceRowID,'|x|','t15.')) else '' end,'		
		',case when len(@SQL_TableTargetJoin)>5 then replace(@SQL_TableTargetJoin,'|x|','t0.') else '' end,'
		',case when len(@SQL_TableTargetWhere)>2 then ' where '+replace(@SQL_TableTargetWhere,'|x|','t0.') else '' end,'
		')

	EXEC(@SQL+@SQL1+@SQL2+@SQL3);
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

XP210:
	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	SET @Liste_ColumnsInTableORG=Null
	SET @StepPraefix='XP210'
	SET @StepText=Concat('','Erstellt @Liste_ColumnsInTableORG mit allen tatsächlich verfügbaren Spalten aus der Testtabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Test]')
	SET @SQL=Concat('SELECT @Liste_ColumnsInTableORG=COALESCE(@Liste_ColumnsInTableORG+N'','', N'''') + ''|x|'' + t1.Spalte
						from (
								SELECT Distinct c.name as Spalte, typ.name as Spaltentyp, c.max_length as Spaltenlaenge, c.column_id as SpaltenID
								from ',@SQL_TableTargetDB,'.sys.columns c
									join ',@SQL_TableTargetDB,'.sys.tables tab ON c.object_id=tab.object_id
									join ',@SQL_TableTargetDB,'.sys.types typ ON c.user_type_id=typ.user_type_id
								WHERE tab.object_id = object_id(''',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG'',''U'')
									and c.name <> ''Zeitstempel_von1''  
									and c.name <> ''Zeitstempel_bis1''  
									and c.name <> ''SchluesselID''  
									and c.name <> ''TableRowID1''
									and c.name <> ''ConnectTableID''
									and c.name <> ''LastChangeOnDate''
									and c.name <> ''HashID''
								) t1
						left join (	
								SELECT Distinct c.name as Spalte, typ.name as Spaltentyp, c.max_length as Spaltenlaenge, c.column_id as SpaltenID
								from ',@SQL_TableTargetDB,'.sys.columns c
									join ',@SQL_TableTargetDB,'.sys.tables tab ON c.object_id=tab.object_id
									join ',@SQL_TableTargetDB,'.sys.types typ ON c.user_type_id=typ.user_type_id
								WHERE tab.object_id = object_id(''',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Test'',''U'')
									and c.name <> ''',replace(@SQL_TableTargetValidTo,'|x|',''),''' 
									and c.name <> ''',replace(@SQL_TableTargetValidFrom,'|x|',''),'''  
								) t2 on t1.Spalte=t2.Spalte
						where t2.Spalte is null
						order by t1.SpaltenID

						SELECT @Liste_ColumnsInTableTest=COALESCE(@Liste_ColumnsInTableTest+N'','', N'''') + ''|x|'' + t1.Spalte
						from (
								SELECT Distinct c.name as Spalte, typ.name as Spaltentyp, c.max_length as Spaltenlaenge, c.column_id as SpaltenID
								from ',@SQL_TableTargetDB,'.sys.columns c
									join ',@SQL_TableTargetDB,'.sys.tables tab ON c.object_id=tab.object_id
									join ',@SQL_TableTargetDB,'.sys.types typ ON c.user_type_id=typ.user_type_id
								WHERE tab.object_id = object_id(''',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Test'',''U'')
									and c.name <> ''',replace(@SQL_TableTargetValidTo,'|x|',''),''' 
									and c.name <> ''',replace(@SQL_TableTargetValidFrom,'|x|',''),''' 
						) t1
						order by t1.SpaltenID
						')

	EXEC sp_EXECutesql @SQL, N'@Liste_ColumnsInTableORG nvarchar(max) OUT, @Liste_ColumnsInTableTest nvarchar(max) OUT', @Liste_ColumnsInTableORG OUT, @Liste_ColumnsInTableTest OUT;
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

XP220:
	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='XP220'
	SET @StepText= Concat('Ergebnisstabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_RAW] erstellen')
	SET @SQL=concat('
		Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_RAW;

		Select 
			t0.TableRowID1
			,t0.SchluesselID
			,',@SQL_TableTargetDefinition1)
	SET @SQL1=@SQL_TableTargetDefinition2
	SET @SQL2=@SQL_TableTargetDefinition3
	SET @SQL3=concat('
			,',replace(@Liste_ColumnsInTableORG,'|x|','t0.'),'
			,t0.Zeitstempel_von1 
			,t0.Zeitstempel_bis1
		into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_RAW
		from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG t0
			',case when @Table1_Valid>0 then concat('left join ',@SQL_Table1_SourceString,' t1 on ',replace(@SQL_TableTargetRowID1,'|x|','t0.'),'=',replace(@SQL_Table1_SourceRowID,'|x|','t1.')) else '' end,'
			',case when @Table2_Valid>0 then concat('left join ',@SQL_Table2_SourceString,' t2 on ',replace(@SQL_TableTargetRowID2,'|x|','t0.'),'=',replace(@SQL_Table2_SourceRowID,'|x|','t2.')) else '' end,'
			',case when @Table3_Valid>0 then concat('left join ',@SQL_Table3_SourceString,' t3 on ',replace(@SQL_TableTargetRowID3,'|x|','t0.'),'=',replace(@SQL_Table3_SourceRowID,'|x|','t3.')) else '' end,'		
			',case when @Table4_Valid>0 then concat('left join ',@SQL_Table4_SourceString,' t4 on ',replace(@SQL_TableTargetRowID4,'|x|','t0.'),'=',replace(@SQL_Table4_SourceRowID,'|x|','t4.')) else '' end,'
			',case when @Table5_Valid>0 then concat('left join ',@SQL_Table5_SourceString,' t5 on ',replace(@SQL_TableTargetRowID5,'|x|','t0.'),'=',replace(@SQL_Table5_SourceRowID,'|x|','t5.')) else '' end,'
			',case when @Table6_Valid>0 then concat('left join ',@SQL_Table6_SourceString,' t6 on ',replace(@SQL_TableTargetRowID6,'|x|','t0.'),'=',replace(@SQL_Table6_SourceRowID,'|x|','t6.')) else '' end,'		
			',case when @Table7_Valid>0 then concat('left join ',@SQL_Table7_SourceString,' t7 on ',replace(@SQL_TableTargetRowID7,'|x|','t0.'),'=',replace(@SQL_Table7_SourceRowID,'|x|','t7.')) else '' end,'
			',case when @Table8_Valid>0 then concat('left join ',@SQL_Table8_SourceString,' t8 on ',replace(@SQL_TableTargetRowID8,'|x|','t0.'),'=',replace(@SQL_Table8_SourceRowID,'|x|','t8.')) else '' end,'
			',case when @Table9_Valid>0 then concat('left join ',@SQL_Table9_SourceString,' t9 on ',replace(@SQL_TableTargetRowID9,'|x|','t0.'),'=',replace(@SQL_Table9_SourceRowID,'|x|','t9.')) else '' end,'		
			',case when @Table10_Valid>0 then concat('left join ',@SQL_Table10_SourceString,' t10 on ',replace(@SQL_TableTargetRowID10,'|x|','t0.'),'=',replace(@SQL_Table10_SourceRowID,'|x|','t10.')) else '' end,'
			',case when @Table11_Valid>0 then concat('left join ',@SQL_Table11_SourceString,' t11 on ',replace(@SQL_TableTargetRowID11,'|x|','t0.'),'=',replace(@SQL_Table11_SourceRowID,'|x|','t11.')) else '' end,'
			',case when @Table12_Valid>0 then concat('left join ',@SQL_Table12_SourceString,' t12 on ',replace(@SQL_TableTargetRowID12,'|x|','t0.'),'=',replace(@SQL_Table12_SourceRowID,'|x|','t12.')) else '' end,'		
			',case when @Table13_Valid>0 then concat('left join ',@SQL_Table13_SourceString,' t13 on ',replace(@SQL_TableTargetRowID13,'|x|','t0.'),'=',replace(@SQL_Table13_SourceRowID,'|x|','t13.')) else '' end,'
			',case when @Table14_Valid>0 then concat('left join ',@SQL_Table14_SourceString,' t14 on ',replace(@SQL_TableTargetRowID14,'|x|','t0.'),'=',replace(@SQL_Table14_SourceRowID,'|x|','t14.')) else '' end,'
			',case when @Table15_Valid>0 then concat('left join ',@SQL_Table15_SourceString,' t15 on ',replace(@SQL_TableTargetRowID15,'|x|','t0.'),'=',replace(@SQL_Table15_SourceRowID,'|x|','t15.')) else '' end,'		
		',case when len(@SQL_TableTargetJoin)>5 then replace(@SQL_TableTargetJoin,'|x|','t0.') else '' end,'
		',case when len(@SQL_TableTargetWhere)>2 then ' where '+replace(@SQL_TableTargetWhere,'|x|','t0.') else '' end,'
		')

	EXEC(@SQL+@SQL1+@SQL2+@SQL3);
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke


XP230:	

	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='XP230'
	SET @StepText= Concat('Erstellt die HashID für die Ergebnistabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_ORG] und speichert das Ergebnis in der Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_HashID]')
	SET @SQL=concat('
		Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_HashID;
			
		Select	Distinct
				SchluesselID
				,TableRowID1
				,Zeitstempel_von1
				,Zeitstempel_bis1
				,Max(Zeitstempel_bis1) over (partition by SchluesselID) as Zeitstempel_bis1_Max
				,',case when @LastChangeOnDate=1 
						then '1' 
						else 'case when cast(Zeitstempel_bis1 as DateTime2)=Max(cast(Zeitstempel_bis1 as DateTime2)) over (partition by SchluesselID, cast(Zeitstempel_bis1 as Date) order by Zeitstempel_bis1)'
					end,' as LastChangeOnDate
				,cast(HASHBYTES(''SHA1'', (select ', Replace(@Liste_ColumnsInTableTest,'|x|',''), ',',Replace(@Liste_ColumnsInTableORG,'|x|',''),' FOR XML RAW)) as varbinary(100)) as HashID
		into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_HashID
		from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_RAW 

			')

	EXEC(@SQL+@SQL1+@SQL2+@SQL3);
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke		

XP240:

	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='XP240'
	SET @StepText=  Concat('HashBereiche bilden und in [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_HashBereiche] speichern.')		
	SET @SQL=Concat('
	Drop Table if exists ', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,'_HashBereiche

	CREATE CLUSTERED INDEX x',replace(@SQL_TableTargetString,'.',''),'_TEMP',@TEMPPraefix,'_HashID ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_HashID
	(SchluesselID ASC, Zeitstempel_von1 ASC) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

	Select SchluesselID
		,Hash_Bereich
		,min(Zeitstempel_von1) as Zeitstempel_von_Hash
		,max(Zeitstempel_bis1) as Zeitstempel_bis_Hash
		,max(LastChangeOnDate) as LastChangeOnDate_Hash
	into ', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,'_HashBereiche
	from (
		Select SchluesselID
			,Zeitstempel_von1
			,Zeitstempel_bis1
			,sum(t1.Hash_Bereich_Anfang) over (partition by SchluesselID order by Zeitstempel_von1 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as Hash_Bereich
			,t1.LastChangeOnDate
		from (
			Select SchluesselID
				,Zeitstempel_von1
				,Zeitstempel_bis1
				,LastChangeOnDate
				,case when HashID<>isnull(lag(HashID)  over (partition by SchluesselID order by Zeitstempel_von1),1) then 1 else 0 end Hash_Bereich_Anfang
			from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_HashID
			',case when @LastChangeOnDate=1 then ' where LastChangeOnDate=1' else '' end,'
			) t1
		) t2
	Group by SchluesselID, Hash_Bereich
	')

	EXEC(@SQL+@SQL1+@SQL2);
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

XP250:
	IF len(@SQL_TableTargetID)>3 and upper(trim(replace(@SQL_TableTargetID,'|x|','')))<>upper('SchluesselID')
		Begin
			SET @StepPraefix='XP250'
			SET @StepText= Concat('Neuen Schlüssel für {',@SQL_TableTargetID,'} in Tabelle [',@SQL_TableTargetString,'_Key ] speichern.')

			SET @SQL=concat('
				Drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Key;

				Select ',replace(@SQL_TableTargetID,'|x|',''),', Row_Number() over (order by ',replace(@SQL_TableTargetID,'|x|',''),') as SchluesselIDNew
				into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Key
				from (Select distinct ',replace(@SQL_TableTargetID,'|x|',''),' from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_RAW) t

				CREATE NONCLUSTERED INDEX xSchluesselIDNew ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Key (',replace(@SQL_TableTargetID,'|x|',''),' ASC) 

				');

			EXEC(@SQL);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''

		End

XP260:
	IF @Ladeverfahren='D' 
		begin 
			if OBJECT_ID(Concat(@SQL_TableTargetString, ''), 'U') IS NOT NULL  
				begin
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix='XP260'
					SET @StepText=  Concat('','Die geänderten Datensätze der letzten ',@DeltaDays,' Tag(e) an die Tabelle [',@SQL_TableTargetString,'] löschen.')
					SET @SQL= CONCAT('Use ',@SQL_TableTargetDB,';
	
					Delete ', @SQL_TableTargetString,'
					from ', @SQL_TableTargetString,' t1
						join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Raw t2 on t1.', Replace(@SQL_TableTargetID,'|x|',''), ' = t2.', Replace(@SQL_TableTargetID,'|x|',''),'

					');	
							 
					EXEC(@SQL+@SQL1+@SQL2+@SQL3);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke		
				end
XP270:
			if OBJECT_ID(Concat(@SQL_TableTargetString, '_DELTA'), 'U') IS NOT NULL  
				begin
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix='XP270'
					SET @StepText=  Concat('','Die geänderten Datensätze der letzten ',@DeltaDays,' Tag(e) an die Tabelle [',@SQL_TableTargetString,'] ergänzen.')
					SET @SQL= CONCAT('
					Insert into ', @SQL_TableTargetString,'
					Select 
						',case when len(@SQL_TableTargetID)>3 and upper(trim(replace(@SQL_TableTargetID,'|x|','')))<>upper('SchluesselID') then 't100.SchluesselIDNew' else 't0.SchluesselID' end,' as SchluesselID
						,',replace(@Liste_ColumnsInTableTest,'|x|','t0.'),'
						,',replace(@Liste_ColumnsInTableORG,'|x|','t0.'),'
						,Dense_Rank() over (partition by ',case when len(@SQL_TableTargetID)>3 and upper(trim(replace(@SQL_TableTargetID,'|x|','')))<>upper('SchluesselID') then 't100.SchluesselIDNew' else 't0.SchluesselID' end,' order by t0.Zeitstempel_von1 DESC) as Rang
						,t98.HashID
						,t99.Hash_Bereich
						,t0.Zeitstempel_von1 as ',replace(@SQL_TableTargetValidFrom,'|x|',''),'
						,isnull(dateadd(',case when @LastChangeOnDate=1 then 'Day' else 'Second' end,',-1,lead(t0.Zeitstempel_von1) over (partition by t0.SchluesselID order by t0.Zeitstempel_von1)),cast(t98.Zeitstempel_bis1_Max as ',case when @LastChangeOnDate=1 then 'date' else 'DateTime2' end,')) as ',replace(@SQL_TableTargetValidTo,'|x|',''),'
						,t99.LastChangeOnDate_Hash as LastChangeOnDate
						,cast(''',convert(nvarchar,GETDATE(),126),''' as DateTime2) as LastChange
					from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_RAW t0
						join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_HashID t98 on t0.TableRowID1=t98.TableRowID1
						join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_HashBereiche t99 on t0.SchluesselID=t99.SchluesselID and t0.Zeitstempel_von1=t99.Zeitstempel_von_Hash
					',case when len(@SQL_TableTargetID)>3 and upper(trim(replace(@SQL_TableTargetID,'|x|','')))<>upper('SchluesselID') 
							then concat(' join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Key t100 on t0.',replace(@SQL_TableTargetID,'|x|',''),'=t100.',replace(@SQL_TableTargetID,'|x|',''))
							else '' end,'
					');	
							 
					EXEC(@SQL+@SQL1+@SQL2+@SQL3);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke		
				end
		end

XP280:
	IF @Ladeverfahren<>'D' 
		begin
			If OBJECT_ID(Concat(@SQL_TableTargetString, ''), 'U') IS NOT NULL  
				begin 
					SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
					SET @StepPraefix='XP280'
					SET @StepText= Concat('Backup von Ergebnisstabelle in Tabelle [',@SQL_TableTargetString,'_Backup] speichern.')
					SET @SQL=concat('
						Drop table if exists ',@SQL_TableTargetString,'_Backup;

						CREATE CLUSTERED INDEX x',replace(@SQL_TableTargetString,'.',''),'_TEMP',@TEMPPraefix,'_HashBereiche ON ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_HashBereiche
						(SchluesselID ASC, Zeitstempel_von_Hash ASC) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

						Select *
						into ',@SQL_TableTargetString,'_Backup 
						from ',@SQL_TableTargetString,' 
		
						EXEC(''CREATE or ALTER VIEW ',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_VIEW AS Select * from ',@SQL_TableTargetString,'_BACKUP'')');

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke
				end

XP290:
			SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
			SET @StepPraefix='XP290'
			SET @StepText= Concat('Ergebnisstabelle [',@SQL_TableTargetString,'] erstellen')
			SET @SQL=concat('
				Drop table if exists ',@SQL_TableTargetString,';

				Select 
					IDENTITY(BIGINT,1,1) as RowID
					',case when len(@SQL_TableTargetID)>3 and upper(trim(replace(@SQL_TableTargetID,'|x|','')))<>upper('SchluesselID') then ',t100.SchluesselIDNew' else ',t0.SchluesselID' end,' as SchluesselID
					,',replace(@Liste_ColumnsInTableTest,'|x|','t0.'),'
					,',replace(@Liste_ColumnsInTableORG,'|x|','t0.'),'
					,Dense_Rank() over (partition by ',case when len(@SQL_TableTargetID)>3 and upper(trim(replace(@SQL_TableTargetID,'|x|','')))<>upper('SchluesselID') then 't100.SchluesselIDNew' else 't0.SchluesselID' end,' order by t0.Zeitstempel_von1 DESC) as Rang
					,t98.HashID
					,t99.Hash_Bereich
					,t0.Zeitstempel_von1 as ',replace(@SQL_TableTargetValidFrom,'|x|',''),'
					,isnull(dateadd(',case when @LastChangeOnDate=1 then 'Day' else 'Second' end,',-1,lead(t0.Zeitstempel_von1) over (partition by t0.SchluesselID order by t0.Zeitstempel_von1)),cast(t98.Zeitstempel_bis1_Max as ',case when @LastChangeOnDate=1 then 'date' else 'DateTime2' end,')) as ',replace(@SQL_TableTargetValidTo,'|x|',''),'
					,t99.LastChangeOnDate_Hash as LastChangeOnDate
					,cast(''',convert(nvarchar,GETDATE(),126),''' as DateTime2) as LastChange
				into ',@SQL_TableTargetString,'
				from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_RAW t0
					join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_HashID t98 on t0.TableRowID1=t98.TableRowID1
					join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_HashBereiche t99 on t0.SchluesselID=t99.SchluesselID and t0.Zeitstempel_von1=t99.Zeitstempel_von_Hash
				',case when len(@SQL_TableTargetID)>3 and upper(trim(replace(@SQL_TableTargetID,'|x|','')))<>upper('SchluesselID') 
						then concat(' join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_Key t100 on t0.',replace(@SQL_TableTargetID,'|x|',''),'=t100.',replace(@SQL_TableTargetID,'|x|',''))
						else '' end,'
				')

			EXEC(@SQL+@SQL1+@SQL2+@SQL3);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

XP300:
			SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
			SET @StepPraefix='XP300'
			SET @StepText=  Concat('Erstelle INDEX x',Replace(@SQL_TableTargetRowIDNEW,'|x|',''),' in der Ergebnistabelle [',@SQL_TableTargetString,']')
			SET @SQL =Concat('Use ',@SQL_TableTargetDB,';

					',case when @Table1_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID1,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID1,'|x|',''),');') else '' end,'
					',case when @Table2_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID2,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID2,'|x|',''),');') else '' end,'
					',case when @Table3_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID3,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID3,'|x|',''),');') else '' end,'
					',case when @Table4_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID4,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID4,'|x|',''),');') else '' end,'
					',case when @Table5_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID5,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID5,'|x|',''),');') else '' end,'
					',case when @Table6_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID6,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID6,'|x|',''),');') else '' end,'
					',case when @Table7_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID7,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID7,'|x|',''),');') else '' end,'
					',case when @Table8_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID8,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID8,'|x|',''),');') else '' end,'
					',case when @Table9_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID9,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID9,'|x|',''),');') else '' end,'
					',case when @Table10_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID10,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID10,'|x|',''),');') else '' end,'
					',case when @Table11_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID11,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID11,'|x|',''),');') else '' end,'
					',case when @Table12_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID12,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID12,'|x|',''),');') else '' end,'
					',case when @Table13_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID13,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID13,'|x|',''),');') else '' end,'
					',case when @Table14_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID14,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID14,'|x|',''),');') else '' end,'
					',case when @Table15_Valid>0 then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetRowID15,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetRowID15,'|x|',''),');') else '' end,'
					',case when len(replace(@SQL_TableTargetID,'|x|','')) >3 and Upper('SchluesselID')<>Upper(trim(replace(@SQL_TableTargetID,'|x|',''))) then concat('CREATE NONCLUSTERED INDEX x',replace(@SQL_TableTargetID,'|x|',''),' on ',@SQL_TableTargetString,' (',replace(@SQL_TableTargetID,'|x|',''),');') else '' end,'
					CREATE NONCLUSTERED INDEX xSchluesselID on ',@SQL_TableTargetString,' (SchluesselID);

					ALTER TABLE ',@SQL_TableTargetString,'
					ADD CONSTRAINT PK_',@SQL_TableTargetName,'_RowID PRIMARY KEY CLUSTERED (',Replace(@SQL_TableTargetRowIDNEW,'|x|',''),');		
					')

			EXEC(@SQL+@SQL1+@SQL2+@SQL3);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

XP310:
			SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
			SET @StepPraefix='XP310'
			SET @StepText=  Concat('VIEW ',@SQL_TableTargetString,'_VIEW auf Ergebnistabelle [',@SQL_TableTargetString,'] umsteuern und ',@SQL_TableTargetString,'_BACKUP löschen.')
			SET @SQL =Concat('Use ',@SQL_TableTargetDB,';

			EXEC(''CREATE or ALTER VIEW ',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_VIEW AS Select * from ',@SQL_TableTargetString,''');
							  
			drop table if exists ',@SQL_TableTargetString,'_BACKUP;
			');
			
			EXEC(@SQL+@SQL1+@SQL2+@SQL3);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke
		end

XP320:

	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='XP320'
	SET @StepText=  Concat('','Die geänderten Datensätze der letzten ',@DeltaDays,' Tag(e) aus Tabelle [',@SQL_TableTargetString,'] in [',@SQL_TableTargetString,'_DELTA] speichern.')
	SET @SQL= CONCAT('Use ',@SQL_TableTargetDB,';
	
	Drop table if exists ',@SQL_TableTargetString,'_DELTA_BACKUP;

	IF OBJECT_ID(Concat(''',@SQL_TableTargetString,''', ''_DELTA''), ''U'') IS NULL
		Select TOP 0 *
		into ',@SQL_TableTargetString,'_DELTA_BACKUP 
		from ',@SQL_TableTargetString,' 
	else
		Select *
		into ',@SQL_TableTargetString,'_DELTA_BACKUP 
		from ',@SQL_TableTargetString,'_DELTA 
				
	EXEC(''CREATE or ALTER VIEW ',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_DELTA_VIEW AS Select * from ',@SQL_TableTargetString,'_DELTA_BACKUP'')

	Drop table if exists ',@SQL_TableTargetString,'_DELTA;

	Select t1.* 
	into ',@SQL_TableTargetString,'_DELTA
	from ',@SQL_TableTargetString,' t1
	join (
			Select distinct ',Replace(@SQL_TableTargetID,'|x|',''),'  
			from ',@SQL_TableTargetString,'
			where  ',replace(@SQL_TableTargetValidFrom,'|x|',''),' >= cast(dateadd(d,-',@DeltaDays,',cast(Getdate() as date)) as DateTime2)
			) t2 on t1.',Replace(@SQL_TableTargetID,'|x|',''), '=t2.',Replace(@SQL_TableTargetID,'|x|',''),'
	
	EXEC(''CREATE or ALTER VIEW ',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_DELTA_VIEW AS Select * from ',@SQL_TableTargetString,'_DELTA'')
	');	
							 
	EXEC(@SQL+@SQL1+@SQL2+@SQL3);
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

XP330:
	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
	SET @StepText=  Concat('','Zeilenanzahl der Tabelle [', @SQL_TableTargetString, '] aus SYS-Tabellen ermitteln.')
	SET @SQL=Concat('SELECT @Zeilenanzahl =(SELECT max(rows) as rowcnt 
						FROM ',@SQL_TableTargetDB,'.sys.partitions WHERE object_id=OBJECT_ID(''', @SQL_TableTargetString, ''', ''U''))')
	
	EXEC sp_EXECutesql @SQL, N'@Zeilenanzahl bigint OUT', @Zeilenanzahl OUT;
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep='XP330', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke
			
AP0:
	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	Set @Konfiguration = concat('
					Zyklus				:',@DaysToFullLoad,'
					TestDurchLauf		:',@TestLoop,'
					Delta				:',@DeltaDays,'
					Fullload			:',@FullloadYears,'
					Ladeverfahren		:',@Ladeverfahren,'
					TEMPPraefix			:',@TEMPPraefix,'
					LastLoad			:',convert(nvarchar,@LastLoad,126),'
					LastFullLoad		:',convert(nvarchar,@LastFullLoad,126),'
					@Table1_Valid		:',@SQL_Table1_SourceString,' (valid=',@Table1_Valid,')
					@Table2_Valid		:',@SQL_Table2_SourceString,' (valid=',@Table2_Valid,')
					@Table3_Valid		:',@SQL_Table3_SourceString,' (valid=',@Table3_Valid,')
					@Table4_Valid		:',@SQL_Table4_SourceString,' (valid=',@Table4_Valid,')
					@Table5_Valid		:',@SQL_Table5_SourceString,' (valid=',@Table5_Valid,')
					@Table6_Valid		:',@SQL_Table6_SourceString,' (valid=',@Table6_Valid,')
					@Table7_Valid		:',@SQL_Table7_SourceString,' (valid=',@Table7_Valid,')
					@Table8_Valid		:',@SQL_Table8_SourceString,' (valid=',@Table8_Valid,')
					@Table9_Valid		:',@SQL_Table9_SourceString,' (valid=',@Table9_Valid,')
					@Table10_Valid		:',@SQL_Table10_SourceString,' (valid=',@Table10_Valid,')
					@Table11_Valid		:',@SQL_Table11_SourceString,' (valid=',@Table11_Valid,')
					@Table12_Valid		:',@SQL_Table12_SourceString,' (valid=',@Table12_Valid,')
					@Table13_Valid		:',@SQL_Table13_SourceString,' (valid=',@Table13_Valid,')
					@Table14_Valid		:',@SQL_Table14_SourceString,' (valid=',@Table14_Valid,')
					@Table15_Valid		:',@SQL_Table15_SourceString,' (valid=',@Table15_Valid,')
					')

AP1:

	If @TEMPLoeschen=1
		Begin
			SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
			SET @StepPraefix='AP1'
			SET @StepText= Concat('','Abschluss: [%TEMP%]-Tabellenliste erstellen')
			SET @SQL=Concat('SELECT @SQL1=COALESCE(@SQL1+N'''', N'''') + isnull(''Drop Table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.''+ t1.name +'';'','''')
									from ',@SQL_TableTargetDB,'.sys.tables t1
										join ',@SQL_TableTargetDB,'.sys.schemas as t2 on t1.schema_id=t2.schema_id and t2.name=''',@SQL_TableTargetSchema,'''
									where t1.name like ''',@SQL_TableTargetName,'_TEMP%''')
					
			EXEC sp_EXECutesql @SQL, N'@SQL1 nvarchar(max) OUT', @SQL1 OUT;
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke
AP2:
			if LEN(@SQL1)>0
				Begin
					SET @StepPraefix='AP2'
					SET @StepText=Concat('','Abschluss: [%TEMP%]-Tabellen löschen.')
					EXEC(@SQL1);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL1=@SQL1, @LogStepRows=@RowCount, @LogStepError=@Fehler
				End
			SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
		End

	if @Fehler>0
		goto Fehlermarke

AP3:
	DECLARE @Liste_Tree1 as nvarchar(max)
	DECLARE @Liste_Tree2 as nvarchar(max)
	DECLARE @Liste_Tree3 as nvarchar(max)
	print @SQL_Table1_SourceString

	SET @Liste_Tree1=''; SET @Liste_Tree2=''; SET @Liste_Tree3=''
	
	Set @Liste_Tree1=Concat(
			    case when @Table1_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID1,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table1_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table1_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table1_SourceString,'U')),'),''',replace(@SQL_Table1_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table1_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table1_SourceString, 'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table2_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID2,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table2_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table2_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table2_SourceString,'U')),'),''',replace(@SQL_Table2_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table2_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table2_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table3_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID3,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table3_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table3_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table3_SourceString,'U')),'),''',replace(@SQL_Table3_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table3_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table3_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table4_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID4,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table4_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table4_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table4_SourceString,'U')),'),''',replace(@SQL_Table4_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table4_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table4_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table5_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID5,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table5_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table5_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table5_SourceString,'U')),'),''',replace(@SQL_Table5_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table5_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table5_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table6_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID6,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table6_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table6_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table6_SourceString,'U')),'),''',replace(@SQL_Table6_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table6_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table6_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table7_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID7,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table7_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table7_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table7_SourceString,'U')),'),''',replace(@SQL_Table7_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table7_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table7_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table8_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID8,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table8_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table8_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table8_SourceString,'U')),'),''',replace(@SQL_Table8_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table8_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table8_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end)
	Set @Liste_Tree2=Concat(
			    case when @Table9_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID9,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table9_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table9_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table9_SourceString,'U')),'),''',replace(@SQL_Table9_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table9_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table9_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table10_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID10,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table10_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table10_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table10_SourceString,'U')),'),''',replace(@SQL_Table10_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table10_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table10_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table11_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID11,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table11_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table11_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table11_SourceString,'U')),'),''',replace(@SQL_Table11_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table11_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table11_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table12_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID12,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table12_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table12_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table12_SourceString,'U')),'),''',replace(@SQL_Table12_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table12_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table12_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table13_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID13,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table13_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table13_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table13_SourceString,'U')),'),''',replace(@SQL_Table13_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table13_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table13_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table14_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID14,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table14_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table14_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table14_SourceString,'U')),'),''',replace(@SQL_Table14_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table14_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table14_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end,'
			  ',case when @Table15_Valid>0 then concat(',(x', replace(@SQL_TableTargetString,'.',''','''),''',',OBJECT_ID(@SQL_TableTargetString,'U'),',''',replace(@SQL_TableTargetID,'|x|',''),''',''',replace(@SQL_TableTargetRowID15,'|x|',''),''',Getdate(),NULL,NULL,''', replace(@SQL_Table15_SourceString,'.',''','''),''',',OBJECT_ID(@SQL_Table15_SourceString,'U'),',(Select Distinct TargetID from ',@SQL_TableRelationTreeString,' where TargetObjectID=',(OBJECT_ID(@SQL_Table15_SourceString,'U')),'),''',replace(@SQL_Table15_SourceRowID,'|x|',''),''',(Select modify_date from ',(Select dbo.TableString_decompose (@SQL_Table15_SourceString,1)),'.sys.tables where object_id=',(OBJECT_ID(@SQL_Table15_SourceString,'U')),'),Null,Null,',@LastChangeOnDate,',''valid'',''',@Ladeverfahren,''',',@LogID,',''',@SQL_TableLoggingString,''')') else '' end)
	
	SET @Liste_Tree3 = '(@MaxRelationID,'''
	
	Print @Liste_Tree1
	Print @SQL_Table1_SourceString
	if len(dbo.CleanAndTrim(@Liste_Tree1,'','',0))>3 or len(dbo.CleanAndTrim(@Liste_Tree2,'','',0))>3
		Begin
			SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
			SET @StepPraefix='AP3'
			SET @StepText=Concat('','Abschluss: Tabellenbeziehungen in [',@SQL_TableRelationTreeString,'] eintragen.')
			SET @SQL=Concat('
			Declare @MaxRelationID as int
			
			SET @MaxRelationID=(SELECT isnull(MAX(RelationID),0) + 1 FROM ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree)

			Delete ',@SQL_TableRelationTreeString,'
						where [TargetTableDB]	=''',@SQL_TableTargetDB,'''
						and [TargetTableSchema]	=''',@SQL_TableTargetSchema,'''
						and [TargetTableName]	=''',@SQL_TableTargetName,''';')

			if len(dbo.CleanAndTrim(@Liste_Tree1,'','',0))>3 
				SET @SQL1=Concat('
					Insert into ',@SQL_TableRelationTreeString,'
					Values ',substring(replace(@Liste_Tree1,'(x',@Liste_Tree3),2,32000),'
								')
			
			if len(dbo.CleanAndTrim(@Liste_Tree2,'','',0))>3 
				SET @SQL2=Concat('
					Insert into ',@SQL_TableRelationTreeString,'
					Values ',substring(replace(@Liste_Tree2,'(x',@Liste_Tree3),2,32000),'
								')

			Set @SQL3=Concat('
					UPDATE ',@SQL_TableRelationTreeString,' 
						SET TargetRows=(SELECT max(p.rows) as Zeilen
									FROM sys.tables AS tbl
									JOIN sys.indexes as i ON i.object_id = tbl.object_id
									JOIN sys.partitions as p ON p.object_id = i.object_id and p.index_id = i.index_id
									JOIN sys.allocation_units as a ON a.container_id = p.partition_id
									where tbl.object_id=',OBJECT_ID(@SQL_TableTargetString,'U'),'),
							TargetSpace=(SELECT ISNULL(8 * SUM(CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END),0.0) as Speicherplatz
									FROM sys.tables AS tbl
									JOIN sys.indexes as i ON i.object_id = tbl.object_id
									JOIN sys.partitions as p ON p.object_id = i.object_id and p.index_id = i.index_id
									JOIN sys.allocation_units as a ON a.container_id = p.partition_id
									where tbl.object_id=',OBJECT_ID(@SQL_TableTargetString,'U'),')		
					FROM ',@SQL_TableLoggingString,'  
					where TargetObjectID=',OBJECT_ID(@SQL_TableTargetString,'U'),'				
		')
			Print @SQL
			Print @SQL1
			Print @SQL2
			Print @SQL3

			EXEC(@SQL+@SQL1+@SQL2+@SQL3);

			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

AP4:
			SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
			SET @StepPraefix='AP4'
			SET @StepText= Concat('','Abschluss: Feldliste für Qlik-Anweisung in Log-Tabelle [',@SQL_TableRelationTreeString,'] extrahieren')
			SET @SQL=Concat('
							SELECT @Liste_ColumnsInTableTarget=COALESCE(@Liste_ColumnsInTableTarget+N''',CHAR(13),','', N'''') + 
								case c.name 
									when ''SchluesselID'' then ''SchluesselID as SchluesselID_',@SQL_TableTargetName,'''
									when ''',Replace(@SQL_TableTargetValidFrom,'|x|',''),''' then ''',Replace(@SQL_TableTargetValidFrom,'|x|',''),' as ',@SQL_TableTargetName,'_',Replace(@SQL_TableTargetValidFrom,'|x|',''),'''
									when ''',Replace(@SQL_TableTargetValidTo,'|x|',''),''' then ''',Replace(@SQL_TableTargetValidTo,'|x|',''),' as ',@SQL_TableTargetName,'_',Replace(@SQL_TableTargetValidTo,'|x|',''),'''
									when ''RowID'' then ''',Replace(@SQL_TableTargetValidTo,'|x|',''),' as RowID_',@SQL_TableTargetName,'''
									else c.name  end
							from ',@SQL_TableTargetDB,'.sys.views v
								join ',@SQL_TableTargetDB,'.sys.columns as c on v.object_id=c.object_id 
								join ',@SQL_TableTargetDB,'.sys.types t ON c.user_type_id=t.user_type_id
							where v.object_id = object_id(''',@SQL_TableTargetString,'_VIEW'',''V'')
							and c.name not in (''Rang'',''HashID'',''LastChangeOnDate'',''LastChange'')
							')

			EXEC sp_EXECutesql @SQL, N'@Liste_ColumnsInTableTarget nvarchar(max) OUT', @Liste_ColumnsInTableTarget OUT;
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke
AP5:
			SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
			SET @StepPraefix='AP5'
			SET @StepText=Concat('','Abschluss: Updaten der Spalte [QlikLoad] in der Log-Tabelle [',@SQL_TableRelationTreeString,'].')
			Set @Qlik_Ladeskript=Concat('Select ',CHAR(13), @Liste_ColumnsInTableTarget,CHAR(13),' FROM ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,' ',CHAR(13),case when @LastChangeOnDate=1 then 'WHERE LastChangeOnDate=1' else '' end)
			SET @SQL=Concat('	
								 Update ',@SQL_TableRelationTreeString,'
								 SET 
										QlikLoad = ''', @Qlik_Ladeskript,''' 
								 from ',@SQL_TableRelationTreeString,'
								 where TargetObjectID=',Object_id(@SQL_TableTargetString,'U'),'
								')
				
			EXEC(@SQL);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,  @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

AP6:	
	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='AP6'
	SET @StepText=Concat('','Abschluss: Aktualisierung der Spalte [Konfig] in der Log-Tabelle [',@SQL_TableRelationTreeString,'].')

	SET @SQL_Konfig=concat('Update ',@SQL_TableRelationTreeString,'
		Set Konfig=''
		Use ',@SQL_TableTargetDB,';
		Execute ',@SQL_TableTargetSchema,'.[TabJoin]
		',@SQL_Konfig)

	SET @SQL_Konfig10=concat(@SQL_Konfig10, '
	''
	from ',@SQL_TableRelationTreeString,' where TargetObjectID=',Object_id(@SQL_TableTargetString,'U')
	)

	EXEC(@SQL_Konfig+@SQL_Konfig1+@SQL_Konfig2+@SQL_Konfig3+@SQL_Konfig4+@SQL_Konfig5+@SQL_Konfig6+@SQL_Konfig7+@SQL_Konfig8+@SQL_Konfig9+@SQL_Konfig10);

	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText,
			@LogStepSQL=@SQL_Konfig,@LogStepSQL1=@SQL_Konfig1, @LogStepSQL2=@SQL_Konfig2, @LogStepSQL3=@SQL_Konfig3, 
			@LogStepSQL4=@SQL_Konfig4,@LogStepSQL5=@SQL_Konfig5, @LogStepSQL6=@SQL_Konfig6, @LogStepSQL7=@SQL_Konfig7, 
			@LogStepSQL8=@SQL_Konfig8,@LogStepSQL9=@SQL_Konfig9, @LogStepSQL10=@SQL_Konfig10, 
			@LogStepRows=@RowCount, @LogStepError=@Fehler 
	
	if @Fehler>0
		goto Fehlermarke

	SET @SQL_Konfig=''; SET @SQL_Konfig1=''; SET @SQL_Konfig2=''; SET @SQL_Konfig3=''; SET @SQL_Konfig4=''; SET @SQL_Konfig5=''; SET @SQL_Konfig6=''; SET @SQL_Konfig7=''; SET @SQL_Konfig8=''; SET @SQL_Konfig9=''; SET @SQL_Konfig10=''
	SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''

		End

	EXEC #LogStep @LogID=@LogID,
						@LogTableProcessMode=@Ladeverfahren,
						@LogTableProcessStatus='FINISHED',
						@LogStep='END',
						@LogStepSQL=@Konfiguration,
						@LogStepRows=@Zeilenanzahl,
						@LogStepStatus='FINISHED'

goto Endmarke

Fehlermarke:

Print 'FEHLER!!!!!!!!!!!!!!!!!!!!!!!'
Print @@Error

Set @SQL= concat('
			Zyklus				:',@DaysToFullLoad,'
			TestDurchLauf		:',@TestLoop,'
			Delta				:',@DeltaDays,'
			Fullload			:',@FullloadYears,'
			Ladeverfahren		:',@Ladeverfahren,'
			TEMPPraefix			:',@TEMPPraefix,'
			LastLoad			:',convert(nvarchar,@LastLoad,126),'
			LastFullLoad		:',convert(nvarchar,@LastFullLoad,126),'
			@Table1_Valid		:',@SQL_Table1_SourceString,' (valid=',@Table1_Valid,')
			@Table2_Valid		:',@SQL_Table2_SourceString,' (valid=',@Table2_Valid,')
			@Table3_Valid		:',@SQL_Table3_SourceString,' (valid=',@Table3_Valid,')
			@Table4_Valid		:',@SQL_Table4_SourceString,' (valid=',@Table4_Valid,')
			@Table5_Valid		:',@SQL_Table5_SourceString,' (valid=',@Table5_Valid,')
			@Table6_Valid		:',@SQL_Table6_SourceString,' (valid=',@Table6_Valid,')
			@Table7_Valid		:',@SQL_Table7_SourceString,' (valid=',@Table7_Valid,')
			@Table8_Valid		:',@SQL_Table8_SourceString,' (valid=',@Table8_Valid,')
			@Table9_Valid		:',@SQL_Table9_SourceString,' (valid=',@Table9_Valid,')
			@Table10_Valid		:',@SQL_Table10_SourceString,' (valid=',@Table10_Valid,')
			@Table11_Valid		:',@SQL_Table11_SourceString,' (valid=',@Table11_Valid,')
			@Table12_Valid		:',@SQL_Table12_SourceString,' (valid=',@Table12_Valid,')
			@Table13_Valid		:',@SQL_Table13_SourceString,' (valid=',@Table13_Valid,')
			@Table14_Valid		:',@SQL_Table14_SourceString,' (valid=',@Table14_Valid,')
			@Table15_Valid		:',@SQL_Table15_SourceString,' (valid=',@Table15_Valid,')
		')


if @Fehler<>99993
	Begin
		Print '#######################################################################'
		Print 'FEHLER!!!!!!!!!!!!!!!!!!!!!!!'
		Print @@Error
		Print '#######################################################################'
		EXEC #LogStep @LogID=@LogID,
				@LogTableProcessStatus='ERROR',
				@LogStep='END',
				@LogStepSQL=@SQL,
				@LogStepRows=@Zeilenanzahl,
				@LogStepStatus='ERROR',
				@LogStepError=@Fehler,
				@LogStepErrorText=@@Error

	End
else
	Begin
		Print '#######################################################################'
		Print 'Ergbnisstabelle ist gemäß @MaxDelay Parameter aktuell!'
		Print '#######################################################################'
		EXEC #LogStep @LogID=@LogID,
				@LogTableProcessStatus='NOLOAD',
				@LogStep='END',
				@LogStepSQL=@Konfiguration,
				@LogStepRows=@Zeilenanzahl,
				@LogStepStatus='FINISHED',
				@LogStepError=@Fehler,
				@LogStepErrorText=@FehlerText
	End

Endmarke:
end
