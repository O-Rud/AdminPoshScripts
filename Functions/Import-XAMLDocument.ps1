Function Import-XAMLDocument {
    <#
    .SYNOPSIS
    Loads XAML Document into memory
    
    .DESCRIPTION
    Loads XAML Document into memory and returns corresponding object. If required loads corresponding assemblies
    
    .PARAMETER XAMLString
    XAML Document. XML or String
    
    .PARAMETER LoadAssemblies
    If specified function will parce XAML document and load all assemblies specified in document before importing XAML. Additionally presentationframework assembly will be loaded
    
    .EXAMPLE
    $XAML = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:wfi="clr-namespace:System.Windows.Forms.Integration;assembly=WindowsFormsIntegration"
        xmlns:wf="clr-namespace:System.Windows.Forms;assembly=System.Windows.Forms"
        xmlns:dvc="clr-namespace:System.Windows.Forms.DataVisualization.Charting;assembly=System.Windows.Forms.DataVisualization">
    <StackPanel Name="StackPanel1">
    <TextBox Name="TextBox1"/>
    <Button Name="Btn1">Button</Button>
    </StackPanel>
    </Window>
    "@
    $Form = Import-XAMLDocument -XAMLString $XAML -LoadAssemblies
    $Form.ShowDialog()

    #>
    param(
        [Parameter (Mandatory = $true)][xml]$XAMLString,
        [switch]$LoadAssemblies
    )
    if ($XAML -isnot [xml]) {$XAML = [xml]$XAML}
    if ($LoadAssemblies) {
        $Assemblies = $XAML.Window.Attributes | foreach-object {$_."#text".split(';')} | Where-object {$_ -match "assembly="} | ForEach-Object {$_.replace('assembly=', '')}
        Add-Type -AssemblyName presentationframework
        foreach ($Assembly in $Assemblies) {
            Add-Type -assemblyName $Assembly
        }
    }
    $Reader = (New-Object System.XML.XMLNodeReader $XAML)
    [Windows.Markup.XamlReader]::Load($Reader)
}