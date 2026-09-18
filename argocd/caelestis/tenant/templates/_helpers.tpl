{{- define "tenant.database" -}}
{{ .Values.tenant.database.name | default (printf "%s-database" .Release.Name) }}
{{- end -}}
