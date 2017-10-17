[CmdletBinding()]
Param([string]$Arguments = "Localhost")

$ScomAPI = New-Object -comObject "MOM.ScriptAPI"
$PropertyBag = $ScomAPI.CreatePropertyBag()

Try {
           

    ## Setting pending values to false to cut down on the number of else statements
       $WUAURebootReq,$CompPendRen,$PendFileRename,$Pending,$SCCM = $false,$false,$false,$false,$false
    $strWUAURebootReq,$strCompPendRen,$strPendFileRename,$strPending,$strSCCM = "No","No","No","No","No"
                        
       ## Setting CBSRebootPend to null since not all versions of Windows has this value
       $CBSRebootPend = $null
    $strCBSRebootPend = "N/A"
                                       
       ## Querying WMI for build version
       $WMI_OS = Get-WmiObject -Class Win32_OperatingSystem -Property BuildNumber, CSName -ComputerName $Arguments -ErrorAction Stop

       ## Making registry connection to the local/remote computer
       $HKLM = [UInt32] "0x80000002"
       $WMI_Reg = [WMIClass] "\\$Arguments\root\default:StdRegProv"
                                       
       ## If Vista/2008 & Above query the CBS Reg Key
       If ([Int32]$WMI_OS.BuildNumber -ge 6001) {
             $RegSubKeysCBS = $WMI_Reg.EnumKey($HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\")
             $CBSRebootPend = $RegSubKeysCBS.sNames -contains "RebootPending"
        If ($CBSRebootPend) {
             $strCBSRebootPend = "Yes"
           }
        Else{
        $strCBSRebootPend = "No"
        }
       }
                                              
       ## Query WUAU from the registry
       $RegWUAURebootReq = $WMI_Reg.EnumKey($HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\")
       $WUAURebootReq = $RegWUAURebootReq.sNames -contains "RebootRequired"
    If ($WUAURebootReq) {
             $strWUAURebootReq = "Yes"
       }      
                                       
       ## Query PendingFileRenameOperations from the registry
       $RegSubKeySM = $WMI_Reg.GetMultiStringValue($HKLM,"SYSTEM\CurrentControlSet\Control\Session Manager\","PendingFileRenameOperations")
       If (($RegSubKeySM.sValue -like '*SEP*') -or $RegSubKeySM.sValue -like '*spool*') {
       }
       Else{
             $RegValuePFRO = $RegSubKeySM.sValue
       }

       ## Query JoinDomain key from the registry - These keys are present if pending a reboot from a domain join operation
       $Netlogon = $WMI_Reg.EnumKey($HKLM,"SYSTEM\CurrentControlSet\Services\Netlogon").sNames
       $PendDomJoin = ($Netlogon -contains 'JoinDomain') -or ($Netlogon -contains 'AvoidSpnSet')
    If ($PendDomJoin) {
             $strPendDomJoin = "Yes"
       }      

       ## Query ComputerName and ActiveComputerName from the registry
       $ActCompNm = $WMI_Reg.GetStringValue($HKLM,"SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName\","ComputerName")            
       $CompNm = $WMI_Reg.GetStringValue($HKLM,"SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName\","ComputerName")

       If (($ActCompNm -ne $CompNm) -or $PendDomJoin) {
           $CompPendRen = $true
        If ($CompPendRen) {
             $strCompPendRen = "Yes"
       }      
       }
                                       
       ## If PendingFileRenameOperations has a value set $RegValuePFRO variable to $true
       If ($RegValuePFRO) {
             $PendFileRename = $true
        $strPendFileRename = "Yes"
        $strRegValuePFRO = $RegValuePFRO
       }
    Else {
    $strRegValuePFRO = "N/A"
    }

       ## Determine SCCM 2012 Client Reboot Pending Status
       ## To avoid nested 'if' statements and unneeded WMI calls to determine if the CCM_ClientUtilities class exist, setting EA = 0
       $CCMClientSDK = $null
       $CCMSplat = @{
           NameSpace='ROOT\ccm\ClientSDK'
           Class='CCM_ClientUtilities'
           Name='DetermineIfRebootPending'
           ComputerName=$Arguments
           ErrorAction='Stop'
       }
      ## Try CCMClientSDK
       Try {
           $CCMClientSDK = Invoke-WmiMethod @CCMSplat
       } Catch [System.UnauthorizedAccessException] {
           $CcmStatus = Get-Service -Name CcmExec -ComputerName $Arguments -ErrorAction SilentlyContinue
           If ($CcmStatus.Status -ne 'Running') {
               Write-Warning "$Arguments`: Error - CcmExec service is not running."
               $CCMClientSDK = $null
           }
       } Catch {
           $CCMClientSDK = $null
       }

       If ($CCMClientSDK) {
           If ($CCMClientSDK.ReturnValue -ne 0) {
                 Write-Warning "Error: DetermineIfRebootPending returned error code $($CCMClientSDK.ReturnValue)"          
             }
             If ($CCMClientSDK.IsHardRebootPending -or $CCMClientSDK.RebootPending) {
                 $SCCM = $true
            If ($SCCM) {
                     $strSCCM = "Yes"
                   } 
             }
       }
            
       Else {
           $SCCM = $null
        $strSCCM = "No"
       }

    $Pending= ($CompPendRen -or $CBSRebootPend -or $WUAURebootReq -or $SCCM -or $PendFileRename)
    If ($Pending) {
             $strPending = "Yes"
       }      
}

Finally {
    
    # Context for alert or performance collection
    $PropertyBag.AddValue("Computer",[string]$WMI_OS.CSName)
    $PropertyBag.AddValue("CBServicing",[string]$strCBSRebootPend)
    $PropertyBag.AddValue("WindowsUpdate",[string]$strWUAURebootReq)
    $PropertyBag.AddValue("CCMClientSDK",[string]$strSCCM)
    $PropertyBag.AddValue("PendComputerRename",[string]$strCompPendRen)
    $PropertyBag.AddValue("PendFileRename",[string]$strPendFileRename)
    $PropertyBag.AddValue("PendFileRenVal",[string]$strRegValuePFRO)
    $PropertyBag.AddValue("RebootPending",[string]$strPending)

    # Send output to SCOM
    $PropertyBag
    ##$ScomAPI.Return($PropertyBag)

} 
