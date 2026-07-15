USE Analysen
GO

-- exec  dbo.UpdateFilterTable_Fallnummer
CREATE or ALTER PROC dbo.UpdateFilterTable_Fallnummer

	@Ladeverfahren as nvarchar(2)	='',	--> Wenn 'F' dann Fulload, wenn 'D' dann Deltaload, Sonst entscheidet das Skript automatische über das Ladeverfahren anhand der Einstellungen
	@TestLoop nvarchar(100)			='',	--> bspw. 'Top 100' für 100 Testdatensätze
	@FullloadYears as int			=5,		--> Jahre die als Fullload geladen werden sollen, 0=Delta-Load

	@SQL_TableSourceDB as nvarchar(200)		= 'replicate',
	@SQL_TableSourceSchema as nvarchar(200)	= 'sap',

	@SQL_TableTargetDB as nvarchar(200)		= 'Analysen',
	@SQL_TableTargetSchema as nvarchar(200)	= 'dbo',	
	@SQL_TableTargetName as nvarchar(200)	= 'Filter_Fallnummer',	

	@SQL_TableLoggingName		as nvarchar(200)='Admin_Log',
	@SQL_TableTabStatusName		as nvarchar(200)='Admin_TabStatus',
	@SQL_TableQlikLoadName		as nvarchar(200)='Admin_QlikLoad'

as
Begin

	PRINT 'Starte Skripabarbeitung für Prozedur UpdateFilterTable_Fallnummer'

	DECLARE @SQL as nvarchar(max)   =''
	DECLARE @SQL1 as varchar(max)	=''
	DECLARE @SQL2 as varchar(max)	=''
	DECLARE @SQL3 as varchar(max)	=''

	DECLARE @START as datetime

	DECLARE @SQL_TableTargetString		as nvarchar(500)=''
	DECLARE @SQL_TableTabStatusString	as nvarchar(500)=''
	DECLARE @SQL_TableQlikLoadString	as nvarchar(200)=''
	DECLARE @SQL_TableLoggingString		as nvarchar(200)=''

	SET @SQL_TableTargetString		=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableTargetName)
	SET @SQL_TableLoggingString		=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableLoggingName)
	SET @SQL_TableTabStatusString	=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableTabStatusName)
	SET @SQL_TableQlikLoadString	=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableQlikLoadName)

	SET @SQL=Concat('DECLARE @TableUpdate as datetime

			Set @TableUpdate  =(Select isnull(t2.last_user_update,t1.modify_date) as Datum
							  from ',@SQL_TableTargetDB,'.sys.tables t1
							  left join ',@SQL_TableTargetDB,'.SYS.DM_DB_INDEX_USAGE_STATS t2 on t1.object_id=t2.object_id
							  where t1.object_id=',isnull(Object_id(@SQL_TableTargetString,'U'),0),')

			if (dateadd(d,6,@TableUpdate)<getdate()
			or @TableUpdate is null
			or ''',@Ladeverfahren,'''=''F'')
			and ',LEN(@TestLoop),'=0
			Begin
				drop table if exists ',@SQL_TableTargetString,'_Temp;

				Select Distinct  
						 cast(t0.FALNR as bigint) as FALNR
						,isnull(t1.istdabei,0) as NFAL
						,isnull(t2.istdabei,0) as NC301S
						,isnull(t3.istdabei,0) as NBEW
						,isnull(t4.istdabei,0) as NAPX
						,isnull(t5.istdabei,0) as VBRK
						,isnull(t6.istdabei,0) as ZNRKT_REKL
						,isnull(t7.istdabei,0) as RKT_EDI
						,isnull(t8.istdabei,0) as NLEI
				into ',@SQL_TableTargetString,'_Temp
				from ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NFAL t0
				left join (Select Distinct  FALNR, 1 as istdabei 
							FROM ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NFAL 
							WHERE YEAR(ERDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(STDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(UPDAT)>year(Getdate())-',@FullloadYears,'		
								) t1 on t0.FALNR=t1.FALNR 											
				left join (Select Distinct  FALNR, 1 as istdabei 
							FROM ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NC301S
							WHERE YEAR(SEDAT)>year(Getdate())-',@FullloadYears,') t2 on t1.FALNR=t2.FALNR 
				left join (Select Distinct  FALNR, 1 as istdabei 
							FROM ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NBEW 
							WHERE  YEAR(ERDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(UPDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(STDAT)>year(Getdate())-',@FullloadYears,'		
								or YEAR(BWIDT)>year(Getdate())-',@FullloadYears,'		
								or (YEAR(BWEDT)<9999 and YEAR(BWEDT)>year(Getdate())-',@FullloadYears,')) t3 on t0.FALNR=t3.FALNR 
				left join (SELECT Distinct  t2.FALNR, 1 as istdabei
							FROM ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NAPX t1
							JOIN ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NAPX_FAL t2 on t1.APXNR=t2.APXNR
							WHERE YEAR(t1.ERDAT)>year(Getdate())-',@FullloadYears,'
								OR YEAR(t1.STDAT)>year(Getdate())-',@FullloadYears,') t4 on t0.FALNR=t4.FALNR  
				left join (SELECT Distinct  ZUONR, 1 as istdabei 
							FROM ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.VBRK 
							WHERE  YEAR(AEDAT)>year(Getdate())-',@FullloadYears,'
								OR YEAR(FKDAT)>year(Getdate())-',@FullloadYears,'
								OR YEAR(ERDAT)>year(Getdate())-',@FullloadYears,') t5 on t0.FALNR=t5.ZUONR
				left join (SELECT Distinct  FALNR, 1 as istdabei 
							FROM ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.ZNRKT_REKL
							WHERE  YEAR(REKL_ST_DAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(REKL_DAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(REKL_ERLDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(ERDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(UPDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(STDAT)>year(Getdate())-',@FullloadYears,') t6 on t0.FALNR=t6.FALNR 
				left join (SELECT Distinct  FALNR, 1 as istdabei 
							FROM ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.[/SMS/RKT_EDI]
							WHERE YEAR(SEDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(ERLDT)>year(Getdate())-',@FullloadYears,'
								or YEAR(PVV_RECDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(ERDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(UPDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(STDAT)>year(Getdate())-',@FullloadYears,') t7 on t0.FALNR=t7.FALNR
				left join (SELECT Distinct  FALNR, 1 as istdabei 
							FROM ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NLEI
							WHERE YEAR(ERDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(UPDAT)>year(Getdate())-',@FullloadYears,'
								or YEAR(IBGDT)>year(Getdate())-',@FullloadYears,'
								or YEAR(PBGDT)>year(Getdate())-',@FullloadYears,') t8 on t0.FALNR=t8.FALNR
				where (t1.istdabei=1 or t2.istdabei=1 OR t3.istdabei=1 OR t4.istdabei=1 OR t5.istdabei=1 OR t6.istdabei=1 OR t7.istdabei=1 OR t8.istdabei=1)
						and cast(t0.FALNR as bigint)>0')
	SET @SQL1=Concat('
				drop table if exists ',@SQL_TableTargetString,';

				Select Top 0
					cast(FALNR as bigint) as FALNR, 0 as NFAL, 0 as NC301S, 0 as NBEW, 0 as NAPX, 0 as VBRK, 0 as ZNRKT_REKL, 0 as RKT_EDI, 0 as NLEI, 0 as NAPX_Neu
				into ',@SQL_TableTargetString,'
				from ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NFAL
			
				CREATE CLUSTERED INDEX x',@SQL_TableTargetName,' ON ', @SQL_TableTargetString,' (FALNR);

				Insert into ',@SQL_TableTargetString,'
				Select Distinct  
						 isnull(cast(t3.FALNR as bigint),t1.FALNR) as FALNR
						,t1.NFAL,t1.NC301S,t1.NBEW,t1.NAPX,t1.VBRK,t1.ZNRKT_REKL,t1.RKT_EDI,t1.NLEI
						,case when t2.FALNR is not null then 1 else 0 end as NAPX_Neu
				from ',@SQL_TableTargetString,'_Temp t1
				left join ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NAPX_FAL t2 on t1.FALNR=cast(t2.FALNR as bigint) 
				left join ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NAPX_FAL t3 on t2.APXNR=t3.APXNR

				drop table if exists ',@SQL_TableTargetString,'_Temp;
			End')

	SET @SQL2=Concat('
	if dateadd(d,6,@TableUpdate)>getdate()
	and @TableUpdate is not null
	and (''',@Ladeverfahren,'''<>''F''
	or ',LEN(@TestLoop),'>0)
		Begin
			drop table if exists ',@SQL_TableTargetString,'_Temp;

			Select cast(t.FALNR as bigint) as FALNR, MAX(t.NFAL) as NFAL, MAX(t.NC301S) as NC301S, MAX(t.NBEW) as NBEW, MAX(t.NAPX) as NAPX, MAX(t.VBRK) as VBRK, MAX(t.ZNRKT_REKL) as ZNRKT_REKL, MAX(t.RKT_EDI) as RKT_EDI, MAX(t.NLEI) as NLEI
			into ',@SQL_TableTargetString,'_Temp
			From (
				Select FALNR,1 as NFAL,0 as NC301S,0 as NBEW,0 as NAPX,0 as VBRK,0 as ZNRKT_REKL,0 as RKT_EDI,0 as NLEI
				from ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NFAL__ct
				where header__timestamp >@TableUpdate
				union
				Select FALNR,0,1,0,0,0,0,0,0
				from ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NC301S__ct
				where header__timestamp >@TableUpdate
				union
				Select FALNR,0,0,1,0,0,0,0,0
				from ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NBEW__ct
				where header__timestamp >@TableUpdate
				union
				Select FALNR,0,0,0,1,0,0,0,0
				from ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NAPX_FAL__ct
				where header__timestamp >@TableUpdate
				union
				Select ZUONR as FALNR,0,0,0,0,1,0,0,0
				from ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.VBRK__ct
				where header__timestamp >@TableUpdate
				union
				Select FALNR,0,0,0,0,0,1,0,0
				from ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.ZNRKT_REKL__ct
				where header__timestamp >@TableUpdate
				union
				Select FALNR,0,0,0,0,0,0,1,0
				from ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.[/SMS/RKT_EDI__ct]
				where header__timestamp >@TableUpdate
				union
				Select FALNR,0,0,0,0,0,0,0,1
				from ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NLEI__ct
				where header__timestamp >@TableUpdate
				) t
			where cast(t.FALNR as bigint) >0
			Group by cast(t.FALNR as bigint)')

	SET @SQL3=Concat('

			drop table if exists ',@SQL_TableTargetString,'_Temp1;

			Select Distinct  
					isnull(cast(t2.FALNR as bigint),t1.FALNR) as FALNR
					,t1.NFAL,t1.NC301S,t1.NBEW,t1.NAPX,t1.VBRK,t1.ZNRKT_REKL,t1.RKT_EDI,t1.NLEI
					,case when t2.FALNR is not null then 1 else 0 end as NAPX_Neu
			into ',@SQL_TableTargetString,'_Temp1
			from ',@SQL_TableTargetString,'_Temp t1
			left join ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NAPX_FAL t2 on t1.FALNR=cast(t2.FALNR as bigint) 

			Delete ',@SQL_TableTargetString,'
			from ',@SQL_TableTargetString,' t1
				join ',@SQL_TableTargetString,'_Temp1 t2 on t1.FALNR=t2.FALNR
		
			Insert into ',@SQL_TableTargetString,'
			Select * from ',@SQL_TableTargetString,'_Temp1

			drop table if exists ',@SQL_TableTargetString,'_Temp1;
			drop table if exists ',@SQL_TableTargetString,'_Temp
		end
		');

	Print @SQL
	Print @SQL1
	Print @SQL2
	Print @SQL3

	Exec(@SQL+@SQL1+@SQL2+@SQL3)

	Print 'Start: ' + CONVERT(NVARCHAR(30), @Start, 113) + '  Ende: ' + CONVERT(NVARCHAR(30), Getdate(), 113) 
	Print 'Dauer: ' + convert(varchar(8),DATEADD(SECOND, datediff(s,@Start, Getdate()), '19000101'),8) 

end;