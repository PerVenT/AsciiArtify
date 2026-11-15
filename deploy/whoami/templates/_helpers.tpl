{{- define "whoami.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "whoami.labels" -}}
app.kubernetes.io/name: {{ include "whoami.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "whoami.selectorLabels" -}}
app.kubernetes.io/name: {{ include "whoami.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
