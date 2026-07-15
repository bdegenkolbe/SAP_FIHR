USE [Analysen]
GO

CREATE OR ALTER PROC [dbo].[ProcStarter]

	@TargetObjectID			as bigint

AS

BEGIN

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
	DECLARE @SQL11 as nvarchar(max)

	Select @SQL10=Konfig
	FROM Analysen.dbo.Admin_TabTree where [TargetObjectID]=@TargetObjectID
	if @SQL10 is not null
		begin
			Set @SQL=substring(cast(@SQL10 as ntext),1,4000) 
			Set @SQL1=substring(cast(@SQL10 as ntext),4001,8000) 
			Set @SQL2=substring(cast(@SQL10 as ntext),8001,12000) 
			Set @SQL3=substring(cast(@SQL10 as ntext),12001,16000) 
			Set @SQL4=substring(cast(@SQL10 as ntext),16001,20000) 
			Set @SQL5=substring(cast(@SQL10 as ntext),20001,24000) 
			Set @SQL6=substring(cast(@SQL10 as ntext),24001,28000) 
			Set @SQL7=substring(cast(@SQL10 as ntext),28001,32000) 
			Set @SQL8=substring(cast(@SQL10 as ntext),32001,36000) 
			Set @SQL9=substring(cast(@SQL10 as ntext),36001,40000) 
			Set @SQL10=substring(cast(@SQL10 as ntext),40001,44000) 
			print (@SQL)
			print (@SQL1)
			print (@SQL2)
			print (@SQL3)
			print (@SQL4)
			print (@SQL5)
			print (@SQL6)
			print (@SQL7)
			print (@SQL8)
			print (@SQL9)
			print (@SQL10)
			exec (@SQL+@SQL1+@SQL2+@SQL3+@SQL4+@SQL5+@SQL6+@SQL7+@SQL8+@SQL9+@SQL10)
		end
	else
		begin
			Print 'Fehler!!! Keine Tabelle mit der ObjektID='+cast(@TargetObjectID as varchar(50))+' gefunden!!!'
		end
END