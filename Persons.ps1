function Create-Hash {
    param (
        [string[]]$inputs
    )
    $combinedString = $inputs -join ""
    $combinedString = [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes(($combinedString).replace(' ','').replace('-' ,'').ToUpper()))
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($combinedString)
    $hash = $sha256.ComputeHash($bytes)
    $uniqueIdentifier = [BitConverter]::ToString($hash).Replace("-", "")
    return $uniqueIdentifier.Substring(0, 12)
}

# Attention, le module POSH-SSH doit etre installé sur chaque serveur hébergeant un agent HelloID
function Get-CSVHublo {
    # Définir les informations de connexion
    $SftpServer = $config.SftpServer
    $SftpUser = $config.SftpUser
    $SftpPassword = $config.SftpPassword
    $ServerDirectoryPath = $config.ServerDirectoryPath
    $fileName = $config.SftpFilename
    $RemoteFilePath = $config.RemoteFilePath + $fileName
    $NewFileName = $(Get-Date -Format "yyyyMMdd_HHmmss") + "_" + $fileName

    # Créer les informations d'identification
    $SecurePassword = ConvertTo-SecureString $SftpPassword -AsPlainText -Force
    $Credential = [System.Management.Automation.PSCredential]::New($SftpUser, $SecurePassword)

    try{
        # Établir une session SFTP
        $SftpSession = New-SFTPSession -ComputerName $SftpServer -Credential $Credential -Force -WarningAction SilentlyContinue

        # Télécharger le fichier
        Get-SFTPItem -SessionId $SftpSession.SessionId -Path $RemoteFilePath -Destination $ServerDirectoryPath -ErrorAction Stop
        Rename-Item -Path $($ServerDirectoryPath + $fileName) -NewName $NewFileName
        
        return $($ServerDirectoryPath + $NewFileName)
    }
    catch{
        return "Erreur : $_"
    }
}

$config = ConvertFrom-Json $configuration;

$CSVpath = Get-CSVHublo

if( $CSVpath -notlike "Erreur*" ) {
    try{
        $contracts = Import-CSV -Path $CSVpath -Delimiter "," | Select-Object *, @{ Name="PersonExternalId"; Expression={ Create-Hash -inputs $_."Nom du remplaçant",$_."Prénom du remplaçant".Substring(0,2),$_."Date de naissance" }}

        $persons = $contracts | Select-Object -Property "PersonExternalId","Nom du remplaçant","Prénom du remplaçant","Matricule","Date de naissance" -Unique

        foreach($p in $persons)
        {
            $person = @{};
            $person["ExternalId"] = $p.PersonExternalId
            $person["FirstName"] = $p."Prénom du remplaçant"
            $person["LastName"] = $p."Nom du remplaçant".toUpper()
            $person["DisplayName"] = "$($p."Nom du remplaçant".toUpper()) $($p."Prénom du remplaçant")"
            $person["BirthDate"] = $p."Date de naissance"
            
            $person["Contracts"] = [System.Collections.ArrayList]@();

            foreach($item in $contracts)
            {
                if($item.PersonExternalId -eq $p.PersonExternalId)
                {
                    $contract = @{}; 
                    $contract["ExternalId"] = $item."Identifiant de la mission";
                    $contract["StartDate"] = $item."Date de debut";
                    $contract["EndDate"] = $item."Date de fin";
                    $contract["Type"] = $item."Statut du remplacant";
                    $contract["Matricule"] = $item."Matricule";
                    $contract["Metier"] = $item."Métier";
                    $contract["UF"] = $item."Nom de l'UF mission réalisee";
                    
                    [void]$person.Contracts.Add($contract);
                }
            }

            Write-Output ($person | ConvertTo-Json -Depth 50)
        }
    }
    #catch [CustomException] { Write-Error $_ }
    catch {
        Write-Error "Erreur lors de l'import du fichier .csv des missions Hublo - Erreur : $_."
    }
}
else {
    Write-Error $CSVpath
}