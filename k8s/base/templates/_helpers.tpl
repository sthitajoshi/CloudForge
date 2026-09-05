{{- define "cloudforge-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cloudforge-app.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "cloudforge-app.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cloudforge-app.labels" -}}
app.kubernetes.io/name: {{ include "cloudforge-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "cloudforge-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cloudforge-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
