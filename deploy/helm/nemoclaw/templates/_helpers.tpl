{{/*
SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
SPDX-FileCopyrightText: Copyright (c) 2026 KubeTEE AI LTD
SPDX-License-Identifier: Apache-2.0
*/}}
{{- define "nemoclaw.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "nemoclaw.fullname" -}}
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

{{- define "nemoclaw.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "nemoclaw.labels" -}}
helm.sh/chart: {{ include "nemoclaw.chart" . }}
{{ include "nemoclaw.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "nemoclaw.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nemoclaw.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "nemoclaw.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "nemoclaw.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "nemoclaw.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}

{{- define "nemoclaw.nvidiaSecretName" -}}
{{- if .Values.existingSecret }}
{{- .Values.existingSecret }}
{{- else }}
{{- include "nemoclaw.fullname" . }}-nvidia
{{- end }}
{{- end }}

{{- define "nemoclaw.tlsSecretName" -}}
{{- if .Values.httpRoute.tls.certManager.secretName }}
{{- .Values.httpRoute.tls.certManager.secretName }}
{{- else }}
{{- printf "%s-tls" (include "nemoclaw.fullname" .) }}
{{- end }}
{{- end }}
