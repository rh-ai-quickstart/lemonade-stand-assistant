# Add Guardrails to the Lemonade Stand Assistant (NeMo Guardrails)

Deploy an AI-powered customer service assistant with built-in safety guardrails using NVIDIA NeMo Guardrails, ensuring family-friendly, compliant interactions for your business.

## Table of Contents

- [Add Guardrails to the Lemonade Stand Assistant (NeMo Guardrails)](#add-guardrails-to-the-lemonade-stand-assistant-nemo-guardrails)
  - [Table of Contents](#table-of-contents)
  - [Detailed description](#detailed-description)
    - [Architecture diagrams](#architecture-diagrams)
    - [Guardrail pipeline](#guardrail-pipeline)
  - [Requirements](#requirements)
    - [Minimum hardware requirements](#minimum-hardware-requirements)
    - [Minimum software requirements](#minimum-software-requirements)
  - [Deploy](#deploy)
    - [Prerequisites](#prerequisites)
    - [Deployment](#deployment)
    - [Configuration options](#configuration-options)
      - [GPU configuration](#gpu-configuration)
      - [NeMo Guardrails configuration](#nemo-guardrails-configuration)
    - [Validating the deployment](#validating-the-deployment)
    - [Delete](#delete)
  - [Technical details](#technical-details)
    - [Architecture](#architecture)
    - [Models](#models)
    - [Deployment configuration](#deployment-configuration)
  - [Reference](#reference)
  - [Tags](#tags)


## Detailed description

Imagine we run a successful lemonade stand and want to deploy a customer service agent so our customers can learn more about our products. We'll want to make sure all conversations with the agent are family friendly, and that it does not promote our rival fruit juice vendors.

This demo showcases how to deploy an AI-powered customer service assistant with multiple guardrails using [NVIDIA NeMo Guardrails](https://github.com/NVIDIA/NeMo-Guardrails) as the orchestration layer. The solution uses your own model endpoint (Model as a Service), protected by a layered pipeline of detectors that monitor inputs and outputs for harmful content, prompt injection attacks, competitor mentions, PII, and language compliance.

**In this demo, we are following these principles:**

1. The LLM is untrusted. All its output must be validated.
2. The user is untrusted. All the input must be validated.
3. Safety checks are layered from cheapest to most expensive — fast local checks run first, model-based checks run only when needed.

The Lemonade Stand Assistant provides an interactive customer service experience for a fictional lemonade stand business. Customers can ask questions about products, ingredients, pricing, and more through a conversational interface.

To ensure safe and appropriate interactions, the system employs multiple AI guardrails arranged in a cost-efficient pipeline:

**Input guardrails (in order of execution):**
- **Message length check**: Rejects messages over 150 words before any model inference
- **[Lingua Language Detector](https://github.com/pemistahl/lingua)**: Ensures inputs are in English only
- **Regex Detector**: Blocks competitor fruit mentions without any model call
- **PII Detection (Presidio)**: Redacts personal data before it reaches the LLM
- **[IBM HAP Detector (Granite Guardian)](https://huggingface.co/ibm-granite/granite-guardian-hap-125m)**: Monitors for hate, abuse, and profanity
- **[Prompt Injection Detector (DeBERTa v3)](https://huggingface.co/protectai/deberta-v3-base-prompt-injection-v2)**: Identifies and blocks manipulation attempts
- **LLM-as-judge (self_check_input)**: Catches subtle off-topic content and ambiguous word meanings that classifiers miss

**Output guardrails:**
- **[IBM HAP Detector (Granite Guardian)](https://huggingface.co/ibm-granite/granite-guardian-hap-125m)**: Validates the model response before it reaches the user
- **PII Detection (Presidio)**: Ensures no personal data leaks in responses

NeMo Guardrails orchestrates these checks using [Colang](https://github.com/NVIDIA/NeMo-Guardrails/blob/develop/docs/user_guides/colang-language-syntax-guide.md) flow definitions and custom Python actions, deployed as a `NemoGuardrails` custom resource managed by the TrustyAI operator.

### Architecture diagrams

> Architecture diagram coming soon.

### Guardrail pipeline

```
User Input
    │
    ├─ [1] Message length check       (custom action, CPU only)
    ├─ [2] Language check             (Lingua service, CPU only)
    ├─ [3] Regex check                (pattern match, CPU only)
    ├─ [4] PII detection              (Presidio, CPU only)
    ├─ [5] HAP check                  (Granite Guardian HF classifier)
    ├─ [6] Prompt injection check     (DeBERTa v3 HF classifier)
    └─ [7] Topic relevance check      (LLM-as-judge via self_check_input)
                │
              Main LLM
                │
    ├─ [8] HAP check on output        (Granite Guardian HF classifier)
    └─ [9] PII detection on output    (Presidio, CPU only)
                │
           User Response
```


## Requirements

### Minimum hardware requirements

This setup requires you to bring your own model endpoint (MaaS). No GPU is required for the NeMo Guardrails service itself or the detector models (CPU-only by default).

**IBM HAP Detector (Granite Guardian HAP 125M):**
- CPU: 1 vCPU (request) / 2 vCPU (limit)
- Memory: 4 GiB (request) / 8 GiB (limit)

**Prompt Injection Detector (DeBERTa v3 Base):**
- CPU: 4 vCPU (request) / 8 vCPU (limit)
- Memory: 16 GiB (request) / 24 GiB (limit)

**Lingua Language Detector:**
- CPU: 1 vCPU (request) / 2 vCPU (limit)
- Memory: 2 GiB (request) / 3 GiB (limit)

**Total Resource Requirements (detectors only):**
- CPU: 6 vCPU (request) / 12 vCPU (limit)
- Memory: 22 GiB (request) / 35 GiB (limit)

> **Note**: If you have GPU resources available and want to improve detector performance, you can enable GPU acceleration for the HAP and prompt injection detectors. See the [Configuration Options](#configuration-options) section for details.

### Minimum software requirements

- Red Hat OpenShift Container Platform
- Red Hat OpenShift AI with TrustyAI operator enabled (for the `NemoGuardrails` CRD)


## Deploy

### Prerequisites

Before deploying, ensure you have:
- Access to a Red Hat OpenShift cluster with OpenShift AI installed and TrustyAI enabled
- A model endpoint (MaaS) with its base URL, model name, and API key
- Cluster admin privileges to create the NeMo Guardrails resources
- `oc` CLI tool installed and configured
- `helm` CLI tool installed

### Deployment

1. Clone the repository:
```bash
git clone https://github.com/rh-ai-quickstart/lemonade-stand-assistant.git
cd lemonade-stand-assistant/nemo-guardrails
```

2. Create a new OpenShift project:
```bash
PROJECT="lemonade-stand"
oc new-project ${PROJECT}
```

3. Create the secret with your model credentials:

```bash
oc create secret generic lemonade-secret \
  --from-literal=api-base=YOUR_MODEL_BASE_URL \
  --from-literal=model-name=YOUR_MODEL_NAME \
  --from-literal=api-key=YOUR_API_KEY \
  --namespace ${PROJECT}
```

> **Note**: The `api-base` should be the full URL including `/v1` suffix (e.g. `https://your-maas-endpoint/v1`). The HAP and prompt injection detectors run as in-cluster KServe InferenceServices and do not require external API credentials.

1. Install using Helm:

```bash
helm install lemonade-stand ./chart --namespace ${PROJECT}
```

### Configuration options

The deployment can be customized through the `values.yaml` file or via `--set` flags. Each detector can be configured to run on GPU or CPU depending on your available resources.

#### GPU configuration

By default, all detector models run on CPU. Each detector supports the following options:

- `useGpu`: Enable GPU acceleration for the detector (default: `false`)
- `resources`: CPU and memory resource requests and limits

**Example: Enable GPU for HAP detector**
```bash
helm install lemonade-stand ./chart --namespace ${PROJECT} \
  --set detectors.hap.useGpu=true
```

**Example: Enable GPU for all configurable detectors**
```bash
helm install lemonade-stand ./chart --namespace ${PROJECT} \
  --set detectors.hap.useGpu=true \
  --set detectors.promptInjection.useGpu=true
```

**Example: Custom resource allocation for the prompt injection detector**
```bash
helm install lemonade-stand ./chart --namespace ${PROJECT} \
  --set detectors.promptInjection.resources.requests.memory=8Gi \
  --set detectors.promptInjection.resources.limits.memory=16Gi
```

#### NeMo Guardrails configuration

The NeMo Guardrails behavior is defined in the `lemonade-config` ConfigMap (`nemo-configmap.yaml`), which contains three files:

| File | Purpose |
|------|---------|
| `config.yaml` | NeMo model config, rail pipeline, and detector endpoints |
| `rails.co` | Colang flow definitions for each guardrail check |
| `actions.py` | Custom Python actions (length check, language check) |

To modify guardrail behavior (thresholds, blocked labels, flows, system prompt), edit `nemo-guardrails/chart/templates/nemo-configmap.yaml` and upgrade the Helm release:

```bash
helm upgrade lemonade-stand ./chart --namespace ${PROJECT}
```

### Validating the deployment

Once deployed, access the Lemonade Stand Assistant UI. You can find the route with:

```bash
echo https://$(oc get route/lemonade-stand-app -n ${PROJECT} --template='{{.spec.host}}')
```

Open the URL in your browser and start asking questions about lemons. Try asking about other fruits or sending an offensive message to verify the guardrails are active.

You can also check the NeMo Guardrails service status:

```bash
oc get nemoguardrails -n ${PROJECT}
```

### Delete

To remove the deployment:

```bash
helm uninstall lemonade-stand --namespace ${PROJECT}
oc delete secret lemonade-secret --namespace ${PROJECT}
```


## Technical details

### Architecture

The Lemonade Stand Assistant (NeMo variant) consists of the following components:

**Guardrails orchestration:**
- **NeMo Guardrails**: NVIDIA's guardrails framework, deployed as a `NemoGuardrails` custom resource via the TrustyAI operator. Executes Colang flows and custom Python actions to enforce the safety pipeline.

**Inference services (detector models):**
- **[IBM HAP Detector (Granite Guardian HAP 125M)](https://huggingface.co/ibm-granite/granite-guardian-hap-125m)**: Detects hate, abuse, and profanity on input and output
- **[Prompt Injection Detector (DeBERTa v3 Base)](https://huggingface.co/protectai/deberta-v3-base-prompt-injection-v2)**: Identifies prompt injection attempts on input
- **[Lingua Language Detector](https://github.com/pemistahl/lingua)**: Validates language compliance (English only) via a custom action calling the Lingua HTTP service

**Application:**
- **Lemonade Stand App**: FastAPI-based web application providing the user interface, communicating with NeMo Guardrails over HTTP

**External dependency:**
- **Main LLM**: Your model endpoint (MaaS). Credentials are injected from a Kubernetes Secret — no values are hardcoded in the ConfigMap.

### Models

| Component | Model | Size | Purpose |
|-----------|-------|------|---------|
| Main LLM | Your model (MaaS) | — | Conversational AI |
| LLM-as-judge | Your model (MaaS) | — | Subtle topic relevance check |
| HAP Detection | Granite Guardian HAP | 125M parameters | Content safety (input & output) |
| Prompt Injection Guard | DeBERTa v3 Base | ~184M parameters | Security (input only) |
| Language Detection | Lingua | Rule-based | Language validation (input only) |

### Deployment configuration

- Detector models are deployed on OpenShift AI using KServe `InferenceService` with the Guardrails Detector HuggingFace runtime
- The Lingua language detector runs as a standard Kubernetes `Deployment`
- NeMo Guardrails is deployed via the `NemoGuardrails` CRD (TrustyAI operator) and mounts the `lemonade-config` ConfigMap
- Model credentials are stored in the `lemonade-secret` Kubernetes Secret and injected as environment variables into the NeMo Guardrails pod — the ConfigMap references them as `${LLM_API_BASE}`, `${LLM_MODEL_NAME}`, and `${LLM_API_KEY}`
- The Colang flows enforce a cost-ordered pipeline: cheap local checks (length, regex, language) run before classifier models, which run before the LLM-as-judge


## Reference

- [NeMo Guardrails](https://github.com/NVIDIA/NeMo-Guardrails) — NVIDIA's guardrails framework
- [TrustyAI Community](https://github.com/trustyai-explainability) — TrustyAI operator and NemoGuardrails CRD
- [Colang Language Guide](https://github.com/NVIDIA/NeMo-Guardrails/blob/develop/docs/user_guides/colang-language-syntax-guide.md) — Reference for writing guardrail flow definitions
- [FMS Orchestr8 variant](../README.md) — The FMS Orchestr8-based version of this same demo


## Tags

* **Industry:** Retail
* **Product:** OpenShift AI, TrustyAI, NeMo Guardrails
* **Use case:** AI safety, content moderation, guardrails
* **Contributor org:** Red Hat
