# Lemonade Stand Assistant

## Acknowledgement

This quickstart is based on the demo by Trusty AI team. It can be found [here](https://github.com/trustyai-explainability/trustyai-llm-demo/tree/lemonade-stand). If you like this demo, we encourage people to contribute to the community of TrustyAI.

## Overview

Imagine we run a successful lemonade stand and want to deploy a customer service agent so our customers can learn more about our products. We'll want to make sure all conversations with the agent are family friendly, and that it does not promote our rival fruit juice vendors.

This demo showcases how to deploy an AI-powered customer service assistant with multiple guardrails to ensure safe, compliant, and on-brand interactions. The solution uses Llama 3.2 as the base language model, protected by three detector models that monitor for harmful content, prompt injection attacks, and language compliance.

**In this demo, we are following these assumptions of principles:** 

1. The LLM is untrusted. All its output must be validated. 
2. The user is untrusted. All the input must be validated.
3. Triggering of specific detectors are monitored and visualized. (Alerts are out of scope but could be done)


**TO ADD** : architecture slide TBA

## Detailed description

The Lemonade Stand Assistant provides an interactive customer service experience for a fictional lemonade stand business. Customers can ask questions about products, ingredients, pricing, and more through a conversational interface.

To ensure safe and appropriate interactions, the system employs multiple AI guardrails:
- **IBM HAP Detector (Granite Guardian)**: Monitors conversations for hate, abuse, and profanity
- **Prompt Injection Detector (DeBERTa v3)**: Identifies and blocks attempts to manipulate the AI assistant
- **Language Detector (XLM-RoBERTa)**: Ensures responses are in English only

Furthemore, there is a:
- **Regex Detector**: Blocks specific text without the use of models. In our case, its other fruits we consider "competitors".

The guardrails orchestrator coordinates these detectors to evaluate inputs and outputs before presenting responses to users.

### See it in action

TODO: an arcade will be added

## Requirements

### Minimum hardware requirements

This demo can be configured to run with different hardware setups depending on your available resources. The detectors can run on either GPU or CPU, and can be selectively enabled or disabled.

#### Default Configuration (All Detectors with GPU)

**Llama 3.2 3B Instruct (Main LLM):**
- CPU: 1 vCPU (request) / 4 vCPU (limit)
- Memory: 8 GiB (request) / 20 GiB (limit)
- GPU: 1 NVIDIA GPU

**IBM HAP Detector (Granite Guardian HAP 125M):**
- CPU: 1 vCPU (request) / 2 vCPU (limit)
- Memory: 4 GiB (request) / 8 GiB (limit)
- GPU: 1 NVIDIA GPU (optional - can run on CPU)

**Prompt Injection Detector (DeBERTa v3 Base):**
- CPU: 1 vCPU (request) / 2 vCPU (limit)
- Memory: 4 GiB (request) / 8 GiB (limit)
- GPU: 1 NVIDIA GPU (optional - can run on CPU)

**Language Detector (XLM-RoBERTa Base):**
- CPU: 1 vCPU (request) / 1 vCPU (limit)
- Memory: 6 GiB (request) / 12 GiB (limit)
- GPU: 1 NVIDIA GPU (optional - can run on CPU)

**Total Resource Requirements (Default - All detectors with GPU):**
- CPU: 4 vCPU (request) / 9 vCPU (limit)
- Memory: 22 GiB (request) / 48 GiB (limit)
- GPU: 4 NVIDIA GPUs (e.g., A10, A100, L40S, T4, or similar)

**Minimum Configuration (LLM with GPU, detectors on CPU):**
- CPU: 4 vCPU (request) / 9 vCPU (limit)
- Memory: 22 GiB (request) / 48 GiB (limit)
- GPU: 1 NVIDIA GPU (for LLM only)

> **Note**: Detectors can be configured to use GPU or CPU. See the Configuration Options section below for details on customizing GPU usage for detectors based on your available resources.

### Minimum software requirements

- Red Hat OpenShift Container Platform
- Red Hat OpenShift AI

### Required user permissions

Standard user. No elevated cluster permissions required.

## Deploy

### Prerequisites

Before deploying, ensure you have:
- Access to a Red Hat OpenShift cluster with OpenShift AI installed
- `oc` CLI tool installed and configured
- `helm` CLI tool installed
- Sufficient GPU resources available in your cluster

### Installation

1. Clone the repository:
```bash
git clone https://github.com/rh-ai-quickstart/lemonade-stand-assistant.git
cd lemonade-stand-assistant
```

2. Create a new OpenShift project:
```bash
PROJECT="lemonade-stand-assistant"
oc new-project ${PROJECT}
```

3. Install using Helm:
```bash
helm install lemonade-stand-assistant ./chart --namespace ${PROJECT}
```

### Configuration Options

The deployment can be customized through the `values.yaml` file. Each detector can be configured to run on GPU or CPU depending on your available resources.

#### GPU Configuration

Each detector supports the following configuration options:

- `useGpu`: Enable GPU acceleration for the detector (default: `true`)
- `resources`: CPU and memory resource requests and limits

**Example: Run all detectors on CPU only (no GPUs required for detectors)**
```bash
helm install lemonade-stand-assistant ./chart --namespace ${PROJECT} \
  --set detectors.hap.useGpu=false \
  --set detectors.promptInjection.useGpu=false \
  --set detectors.language.useGpu=false
```

**Example: Run only HAP detector with GPU, others on CPU**
```bash
helm install lemonade-stand-assistant ./chart --namespace ${PROJECT} \
  --set detectors.hap.useGpu=true \
  --set detectors.promptInjection.useGpu=false \
  --set detectors.language.useGpu=false
```

**Example: Custom resource allocation for CPU-only HAP detector**
```bash
helm install lemonade-stand-assistant ./chart --namespace ${PROJECT} \
  --set detectors.hap.useGpu=false \
  --set detectors.hap.resources.requests.memory=2Gi \
  --set detectors.hap.resources.limits.memory=4Gi
```

#### Available Detectors

The following detectors are always deployed and can be configured in `values.yaml` under the `detectors` section:

- **hap**: IBM HAP Detector (Granite Guardian) - Monitors for hate, abuse, and profanity
- **promptInjection**: Prompt Injection Detector (DeBERTa v3) - Identifies prompt injection attempts
- **language**: Language Detector (XLM-RoBERTa) - Validates language compliance (English only)

### Validating the deployment

Once deployed, access the Lemonade Stand Assistant UI. You can find the route with:

```bash
echo https://$(oc get route/lemonade-stand-assistant -n ${PROJECT} --template='{{.spec.host}}')
```

Open the URL in your browser and start asking questions about lemonade and other fruits!

### Uninstall

To remove the deployment:

```bash
helm uninstall lemonade-stand-assistant --namespace ${PROJECT}
```

## References 

<!-- 

*Section optional.* Remember to remove if do not use.

Include links to supporting information, documentation, or learning materials.

--> 

## Technical details

### Architecture

The Lemonade Stand Assistant consists of the following components:

**Inference Services:**
- **Llama 3.2 3B Instruct**: Main language model for generating responses
- **IBM HAP Detector (Granite Guardian HAP 125M)**: Detects hate, abuse, and profanity
- **Prompt Injection Detector (DeBERTa v3 Base)**: Identifies prompt injection attempts
- **Language Detector (XLM-RoBERTa Base)**: Validates language compliance (English only)

**Orchestration:**
- **Guardrails Orchestrator**: Coordinates detector models using FMS Orchestr8
- **Shiny Application**: Provides the user interface for customer interactions

### Models

| Component | Model | Size | Purpose |
|-----------|-------|------|---------|
| Main LLM | Llama 3.2 3B Instruct | 3B parameters | Conversational AI |
| HAP Detection | Granite Guardian HAP | 125M parameters | Content safety |
| Prompt Injection Guard | DeBERTa v3 Base | ~184M parameters | Security |
| Language Detection | XLM-RoBERTa Base | ~270M parameters | Language validation |

### Deployment Configuration

All models are deployed as KServe InferenceServices on OpenShift AI using:
- vLLM runtime for the main LLM (optimized inference)
- Guardrails Detector runtime for all detector models
- Raw deployment mode for better control and observability

## Tags

<!-- CONTRIBUTOR TODO: add metadata and tags for publication

TAG requirements: 
	* Title: max char: 64, describes quickstart (match H1 heading) 
	* Description: max char: 160, match SHORT DESCRIPTION above
	* Industry: target industry, ie. Healthcare OR Financial Services
	* Product: list primary product, ie. OpenShift AI OR OpenShift OR RHEL 
	* Use case: use case descriptor, ie. security, automation, 
	* Contributor org: defaults to Red Hat unless partner or community
	
Additional MIST tags, populated by web team.

-->
