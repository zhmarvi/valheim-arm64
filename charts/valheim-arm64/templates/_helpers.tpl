{{/* Expand the chart name. */}}
{{- define "valheim.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a release-scoped resource name. */}}
{{- define "valheim.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Chart label value. */}}
{{- define "valheim.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Immutable selector labels. */}}
{{- define "valheim.selectorLabels" -}}
app.kubernetes.io/name: {{ include "valheim.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Standard labels; user labels cannot replace chart identity labels. */}}
{{- define "valheim.labels" -}}
{{- $labels := dict
  "helm.sh/chart" (include "valheim.chart" .)
  "app.kubernetes.io/name" (include "valheim.name" .)
  "app.kubernetes.io/instance" .Release.Name
  "app.kubernetes.io/version" .Chart.AppVersion
  "app.kubernetes.io/managed-by" .Release.Service
  "app.kubernetes.io/component" "server"
  "app.kubernetes.io/part-of" "valheim-arm64"
-}}
{{- $labels = merge $labels (.Values.commonLabels | default dict) -}}
{{- toYaml $labels }}
{{- end }}

{{/* Merge resource-specific labels without allowing identity overrides. */}}
{{- define "valheim.mergedLabels" -}}
{{- $root := index . 0 -}}
{{- $custom := index . 1 | default dict -}}
{{- $labels := include "valheim.labels" $root | fromYaml -}}
{{- $labels = merge $labels $custom -}}
{{- toYaml $labels }}
{{- end }}

{{/* Resolve the container image, preferring an immutable digest. */}}
{{- define "valheim.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) -}}
{{- end -}}
{{- end }}

{{/* Resolve the Secret containing SERVER_PASSWORD. */}}
{{- define "valheim.secretName" -}}
{{- default (include "valheim.fullname" .) .Values.server.existingSecret.name -}}
{{- end }}

{{/* Reject ambiguous or incomplete password configuration. */}}
{{- define "valheim.validateValues" -}}
{{- if and .Values.server.password .Values.server.existingSecret.name -}}
{{- fail "set only one of server.password or server.existingSecret.name" -}}
{{- end -}}
{{- if and (not .Values.server.password) (not .Values.server.existingSecret.name) -}}
{{- fail "a server password is required: set server.existingSecret.name (recommended) or server.password" -}}
{{- end -}}
{{- end }}
