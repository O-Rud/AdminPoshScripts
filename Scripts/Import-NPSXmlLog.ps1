Paam(
[string]$path
)
[Reflection.Assembly]::LoadWithPartialName('System.Xml.Linq')
$XmlReaderSettings = [System.Xml.XmlReaderSettings]::new()
$XmlReaderSettings.ConformanceLevel = 'Fragment'
$reader = [System.Xml.XmlReader]::create($path,$XmlReaderSettings)
While($reader.read()){
    switch ($reader.NodeType){
        ([System.Xml.XmlNodeType]::Element){
            $ht = [ordered]@{}
            $e = [System.Xml.Linq.XElement]::ReadFrom($reader)
            foreach ($node in $e.Nodes()){
                $ht[$node.Name.LocalName] = $node.Value
            }
            [pscustomobject]$ht
        }
    }
}