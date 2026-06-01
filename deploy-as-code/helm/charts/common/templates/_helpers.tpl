{{- define "common.name" -}}
{{- $envOverrides := index .Values (tpl (default .Chart.Name .Values.name) .) -}} 
{{- $baseCommonValues := .Values.common | deepCopy -}}
{{- $values := dict "Values" (mustMergeOverwrite $baseCommonValues .Values $envOverrides) -}}
{{- with mustMergeOverwrite . $values -}}
{{- default .Chart.Name .Values.name -}}    
{{- end }}
{{- end }}

{{- define "common.labels" -}}
app: {{ template "common.name" . }}
{{- if .Values.labels.group }}      
group: {{ .Values.labels.group }}  
{{- end }}  
{{- range $key, $val := .Values.additionalLabels }}
{{ $key }}: {{ $val | quote }}
{{- end }}    
{{- end }}

{{- define "common.imageTag" -}}
{{- $chartName := .chartName | default "" -}}
{{- .tag | default (index .Values.images.overrides $chartName) | default .Values.images.defaultTag | default .Values.global.image.tag | required "Image tag: set images.defaultTag in environments/<HELMFILE_ENV>.yaml (or image.tag / images.overrides.<chart>)" -}}
{{- end -}}

{{- define "common.image" -}}
{{- $tag := include "common.imageTag" . -}}
{{- if contains "/" .repository -}}
{{- printf "%s:%s" .repository $tag -}}
{{- else -}}
{{- $registry := .Values.images.registry | default .Values.global.containerRegistry -}}
{{- printf "%s/%s:%s" $registry .repository $tag -}}
{{- end -}}
{{- end -}}