# capt-cluster

このリポジトリは、MicroK8s 上の管理クラスタから Tinkerbell / Cluster API
を使ってベアメタル Kubernetes クラスタを作り、そのワークロードクラスタ上に
Argo CD、MetalLB、openstack-helm を配置するための設定です。

## 全体像

この構成には Argo CD が 2 つあります。

- 管理クラスタの Argo CD
- ワークロードクラスタの Argo CD

管理クラスタの Argo CD は `argocd/` 配下を同期します。ここでは Tinkerbell、
Cluster API、ハードウェア定義、ワークロードクラスタ本体を作ります。

ワークロードクラスタの Argo CD は、ワークロードクラスタ内にインストールされます。
OpenStack はこのワークロードクラスタ側の Argo CD からデプロイします。

## ディレクトリ構成

- `bootstrap.sh`: 管理ホストに MicroK8s と管理クラスタ側 Argo CD を入れるスクリプト
- `argocd/`: 管理クラスタ側 Argo CD が同期する Application 定義
- `cluster/`: ワークロードクラスタ本体と addon の定義
- `cluster/addons/`: ワークロードクラスタへ追加する CNI、MetalLB、Argo CD など
- `cluster/argocd/`: ワークロードクラスタ側 Argo CD が同期する Application 定義
- `cluster/argocd/openstack/`: openstack-helm の Application と values
- `hardware/`: Tinkerbell の Hardware / BMC 定義
- `system/`: 管理クラスタ側に入れる CAPI / Tinkerbell 関連コンポーネント

## 初期セットアップ

管理ホストで次を実行します。

```bash
./bootstrap.sh
```

このスクリプトは次を行います。

- MicroK8s のインストール
- 管理クラスタ側 Argo CD のインストール
- Argo CD の `argocd-server` を NodePort 化
- Kustomize で Helm を使えるように設定
- `argocd/app-of-apps.yaml` の適用

## 管理クラスタ側 Argo CD

管理クラスタ側 Argo CD は、ワークロードクラスタを作るための Argo CD です。
`argocd/` 配下の Application を同期します。

状態確認:

```bash
kubectl -n argocd get svc argocd-server
kubectl -n argocd get applications
```

初期パスワード:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

## ワークロードクラスタ側 Argo CD

ワークロードクラスタ側 Argo CD は、`cluster/addons/helmchartproxy-argocd.yaml`
でインストールされます。

アクセス先:

```text
https://172.16.100.10
```

この IP は MetalLB で払い出しています。

初期パスワード:

```bash
ssh -i ~/.ssh/id_ed25519 tinkerbell@172.16.10.11 \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf -n argocd \
  get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo'
```

状態確認:

```bash
ssh -i ~/.ssh/id_ed25519 tinkerbell@172.16.10.11 \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf -n argocd \
  get pods,svc,applications'
```

## MetalLB

MetalLB はワークロードクラスタにインストールされます。

設定ファイル:

```text
cluster/addons/helmchartproxy-metallb.yaml
cluster/addons/metallb-config.yaml
```

現在のアドレスプール:

```text
172.16.100.10-172.16.100.99
```

ワークロードクラスタ側 Argo CD は、この範囲の先頭である
`172.16.100.10` を固定で使います。

このクラスタでは control-plane ノードだけで構成されているため、
MetalLB の speaker は `speaker.ignoreExcludeLB: true` を有効にしています。
これがないと、control-plane ノードから LoadBalancer IP が広告されません。

MetalLB の状態確認:

```bash
ssh -i ~/.ssh/id_ed25519 tinkerbell@172.16.10.11 \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf -n metallb-system \
  get ipaddresspool,l2advertisement,pods'
```

## OpenStack のデプロイ

OpenStack は、ワークロードクラスタ側 Argo CD からデプロイします。
管理クラスタ側 Argo CD から直接 OpenStack を同期する構成ではありません。

流れは次の通りです。

1. 管理クラスタ側 Argo CD がワークロードクラスタを作る
2. ワークロードクラスタに Argo CD がインストールされる
3. `cluster/addons/openstack-bootstrap-app.yaml` がワークロードクラスタへ入る
4. ワークロードクラスタ側 Argo CD が `cluster/argocd` を同期する
5. `cluster/argocd/openstack` の openstack-helm Application 群が作られる

OpenStack bootstrap の定義:

```text
cluster/addons/openstack-bootstrap-app.yaml
cluster/addons/crs-openstack-bootstrap.yaml
```

OpenStack Application の定義:

```text
cluster/argocd/openstack
```

OpenStack の Application 状態確認:

```bash
ssh -i ~/.ssh/id_ed25519 tinkerbell@172.16.10.11 \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf -n argocd \
  get applications'
```

OpenStack の Pod 確認:

```bash
ssh -i ~/.ssh/id_ed25519 tinkerbell@172.16.10.11 \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf -n openstack \
  get pods,svc'
```

## よく使う確認コマンド

管理クラスタ側:

```bash
kubectl -n argocd get applications
kubectl -n tinkerbell get cluster,machines
```

ワークロードクラスタのノード:

```bash
ssh -i ~/.ssh/id_ed25519 tinkerbell@172.16.10.11 \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes'
```

ワークロードクラスタ側 Argo CD の Service:

```bash
ssh -i ~/.ssh/id_ed25519 tinkerbell@172.16.10.11 \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf -n argocd \
  get svc argocd-server -o wide'
```

Argo CD の Application 一覧:

```bash
ssh -i ~/.ssh/id_ed25519 tinkerbell@172.16.10.11 \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf -n argocd \
  get applications'
```

## 注意点

`argocd/` は管理クラスタ側 Argo CD 用です。

`cluster/argocd/` はワークロードクラスタ側 Argo CD 用です。

OpenStack を変更する場合は、基本的に `cluster/argocd/openstack/` 配下を編集します。
