# MySQL Technology Cafe 13

「MySQL Technology Cafe #13」で利用した、デモ環境の構築方法、資材置き場です。

インストール方法は、[MySQL Operator for Kubernetes](https://github.com/mysql/mysql-operator)をベースとしてますが、一部カスタマイズしています。

環境は、OCI（Oracle Cloud Infrastructure）前提となります。

## Installation of the MySQL Operator

Namespace `mysql-operator` を作成します。

```
kubectl create ns mysql-operator
```

MySQL Operator をインストールします。

```
kubectl apply -f https://raw.githubusercontent.com/mysql/mysql-operator/trunk/deploy/deploy-crds.yaml
```

```
kubectl apply -f https://raw.githubusercontent.com/mysql/mysql-operator/trunk/deploy/deploy-operator.yaml
```

Namespace `mysql-operator` に MySQL Operator がインストールされたことを確認します。

```
kubectl get deployment -n mysql-operator mysql-operator
```

```
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
mysql-operator   1/1     1            1           1h
```

## Using the MySQL Operator to setup a MySQL InnoDB Cluster

InnoDBクラスタを作成する上で必要となる、MySQLのrootユーザ情報（パスワード）をSecretに登録します。

```
kubectl create secret generic  mypwds --from-literal=rootPassword="mysqlp@ssword"
```

サンプルクラスタのマニフェストを作成します。このサンプルクラスタは、​​3つのMySQLサーバーインスタンスと1つのMySQLルーターインスタンスを持つInnoDBクラスタです。

```
vim sample-cluster.yaml
```

```
apiVersion: mysql.oracle.com/v2alpha1
kind: InnoDBCluster
metadata:
  name: mycluster
spec:
  secretName: mypwds
  instances: 3
  router:
    instances: 1
```

マニフェストを適用します。

```
kubectl apply -f sample-cluster.yaml
```

InnoDBクラスタの状況を確認します。

```
kubectl get innodbcluster --watch
```

```
NAME          STATUS    ONLINE   INSTANCES   ROUTERS   AGE
mycluster     PENDING   0        3           1         10s
```

## Connecting to the MYSQL InnoDB Cluster

InnoDBクラスタに接続する、KubernetesクラスタのServiceを確認します。後のWordPressと連携する際に必要となります。

```
kubectl get service mycluster
```

```
NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                               AGE
mycluster     ClusterIP   10.43.203.248   <none>        6446/TCP,6448/TCP,6447/TCP,6449/TCP   1h
```

エクスポートされたポートは、MySQLプロトコルおよびXプロトコルの読み取り/書き込み、読み取り専用ポートです。

```
kubectl describe service mycluster
```

```
Name:              mycluster
Namespace:         default
Labels:            mysql.oracle.com/cluster=mycluster
                   tier=mysql
Annotations:       <none>
Selector:          component=mysqlrouter,mysql.oracle.com/cluster=mycluster,tier=mysql
Type:              ClusterIP
IP Families:       <none>
IP:                10.43.203.248
IPs:               <none>
Port:              mysql  6446/TCP
TargetPort:        6446/TCP
Endpoints:         <none>
Port:              mysqlx  6448/TCP
TargetPort:        6448/TCP
Endpoints:         <none>
Port:              mysql-ro  6447/TCP
TargetPort:        6447/TCP
Endpoints:         <none>
Port:              mysqlx-ro  6449/TCP
TargetPort:        6449/TCP
Endpoints:         <none>
Session Affinity:  None
Events:            <none>
```

## Installation of WordPress

### NFS Server

NFSサーバを構築します。最初にPersistentVolumeClaimを作成します。

```
vim nfs-pvc.yaml
```

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc
spec:
  storageClassName: "oci-bv"
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
```

マニフェストを適用します。

```
kubectl apply -f nfs-pvc.yaml
```

NFSサーバを作成します。

```
vim nfs-server.yaml
```

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-server
spec:
  replicas: 1
  selector:
    matchLabels:
      role: nfs-server
  template:
    metadata:
      labels:
        role: nfs-server
    spec:
      containers:
      - name: nfs-server
        image: gcr.io/google_containers/volume-nfs:0.8
        ports:
          - name: nfs
            containerPort: 2049
          - name: mountd
            containerPort: 20048
          - name: rpcbind
            containerPort: 111
        securityContext:
          privileged: true
        volumeMounts:
          - mountPath: /exports
            name: nfs-local-storage
      volumes:
        - name: nfs-local-storage
          persistentVolumeClaim:
            claimName: nfs-pvc
```

マニフェストを適用します。

```
kubectl apply -f nfs-server.yaml
```

WordPressのPersistentVolumeから指定するNFSのServiceを作成します。

```
vim nfs-service.yaml
```

```
apiVersion: v1
kind: Service
metadata:
  name: nfs-service
spec:
  ports:
    - name: nfs
      port: 2049
    - name: mountd
      port: 20048
    - name: rpcbind
      port: 111
  selector:
    role: nfs-server
```

マニフェストを適用します。

```
kubectl apply -f nfs-service.yaml
```

WordPressのPersistentVolumeから指定するNFSのServiceのClusterIPを確認します。

```
kubectl get services
```

```
NAME                  TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)                               AGE
kubernetes            ClusterIP   10.96.0.1     <none>        443/TCP                               46m
mycluster             ClusterIP   10.96.78.48   <none>        6446/TCP,6448/TCP,6447/TCP,6449/TCP   23m
mycluster-instances   ClusterIP   None          <none>        3306/TCP,33060/TCP,33061/TCP          23m
nfs-service           ClusterIP   10.96.3.133   <none>        2049/TCP,20048/TCP,111/TCP            7m40s
```

### WordPress

WordPressのPersistentVolumeを作成します。

```
vim wordpress-pv.yaml
```

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: wordpress-pv
  labels:
    type: local
spec:
  storageClassName: wordpress
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: xx.xx.xx.xx #「nfs-service」のCLUSTER-IPを定義
    path: /
```

マニフェストを適用します。

```
kubectl apply -f wordpress-pv.yaml
```

WordPressのPersistentVolumeClaimを作成します。

```
vim wordpress-pvc.yaml
```

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wordpress-pvc
  labels:
    app: wordpress
    tier: wordpress
spec:
  storageClassName: wordpress
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
```

マニフェストを適用します。

```
kubectl apply -f wordpress-pvc.yaml
```

WordPressのPersistentVolumeとPersistentVolumeClaimが連携していることを確認します。

```
kubectl get persistentvolumes,persistentvolumeclaims
```

```
NAME                                                                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                         STORAGECLASS   REASON   AGE
persistentvolume/csi-c53808cb-59ad-4d7a-b66e-b4270a8865f6                                                   50Gi       RWO            Delete           Bound    default/nfs-pvc               oci-bv                  5m27s
persistentvolume/ocid1.volume.oc1.ap-osaka-1.abvwsljr7qxpebackkzjawgn2lvzuuexhyd6b3ptp6jcprrogmqkwuyuawzq   50Gi       RWO            Delete           Bound    default/datadir-mycluster-0   oci                     20m
persistentvolume/ocid1.volume.oc1.ap-osaka-1.abvwsljrfjsqnzq2nsqzo3myni2nksdvnqsmdfltevu42mhmlbdriobfauqa   50Gi       RWO            Delete           Bound    default/datadir-mycluster-1   oci                     18m
persistentvolume/ocid1.volume.oc1.ap-osaka-1.abvwsljrvoadedytyhdxcqef27lsaeiur4scdkpazfcnp25wbvkwdz7ncfgq   50Gi       RWO            Delete           Bound    default/datadir-mycluster-2   oci                     16m
persistentvolume/wordpress-pv                                                                               50Gi       RWX            Delete           Bound    default/wordpress-pvc         wordpress               41s

NAME                                        STATUS   VOLUME                                                                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/datadir-mycluster-0   Bound    ocid1.volume.oc1.ap-osaka-1.abvwsljr7qxpebackkzjawgn2lvzuuexhyd6b3ptp6jcprrogmqkwuyuawzq   50Gi       RWO            oci            21m
persistentvolumeclaim/datadir-mycluster-1   Bound    ocid1.volume.oc1.ap-osaka-1.abvwsljrfjsqnzq2nsqzo3myni2nksdvnqsmdfltevu42mhmlbdriobfauqa   50Gi       RWO            oci            18m
persistentvolumeclaim/datadir-mycluster-2   Bound    ocid1.volume.oc1.ap-osaka-1.abvwsljrvoadedytyhdxcqef27lsaeiur4scdkpazfcnp25wbvkwdz7ncfgq   50Gi       RWO            oci            16m
persistentvolumeclaim/nfs-pvc               Bound    csi-c53808cb-59ad-4d7a-b66e-b4270a8865f6                                                   50Gi       RWO            oci-bv         5m40s
persistentvolumeclaim/wordpress-pvc         Bound    wordpress-pv                                                                               50Gi       RWX            wordpress      22s
```

WordPressのマニフェストを作成します。

```
vim wordpress.yaml
```

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
        - image: wordpress:5.6.2
          name: wordpress
          env:
          #Service名「mycluster:6446」を定義
          - name: WORDPRESS_DB_HOST
            value: mycluster:6446
          #MySQLのデータベースパスワードを参照する定義
          - name: WORDPRESS_DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: mypwds
                key: rootPassword
          ports:
            - containerPort: 80
              name: wordpress
          #Podのマウントパス定義
          volumeMounts:
            - name: wordpress-local-storage
              mountPath: /var/www/html
      #「wordpress-pvc」を指定する定義
      volumes:
        - name: wordpress-local-storage
          persistentVolumeClaim:
            claimName: wordpress-pvc
```

マニフェストを適用します。

```
kubectl apply -f wordpress.yaml
```

WordPressのPodがRunnninngであることを確認します。

```
kubectl get pods
```

```
NAME                          READY   STATUS    RESTARTS   AGE
mycluster-0                   2/2     Running   0          24m
mycluster-1                   2/2     Running   0          22m
mycluster-2                   2/2     Running   0          20m
mycluster-router-x584w        1/1     Running   0          22m
nfs-server-788c45b6f5-lfsx2   1/1     Running   0          10m
wordpress-598746d47b-dpc47    1/1     Running   0          66s
```

WordPress Serviceのマニフェストを作成します。

```
vim wordpress-service.yaml
```

```
apiVersion: v1
kind: Service
metadata:
  name: wordpress-service
  labels:
    app: wordpress
spec:
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  selector:
    app: wordpress
```

マニフェストを適用します。

```
kubectl apply -f wordpress-service.yaml
```

EXTERNAL-IPが表示されます。実際にブラウザでアクセスすると、WordPressのセットアップ画面が表示されます。

```
kubectl get services
```

```
NAME                  TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)                               AGE
kubernetes            ClusterIP      10.96.0.1       <none>          443/TCP                               55m
mycluster             ClusterIP      10.96.78.48     <none>          6446/TCP,6448/TCP,6447/TCP,6449/TCP   32m
mycluster-instances   ClusterIP      None            <none>          3306/TCP,33060/TCP,33061/TCP          32m
nfs-service           ClusterIP      10.96.3.133     <none>          2049/TCP,20048/TCP,111/TCP            16m
wordpress-service     LoadBalancer   10.96.172.233   168.xx.xx.xx     80:32151/TCP                          44s
```

## Connect to MySQL

### 1.MySQL Operator Pod に接続してMySQL Shellを実行する場合

```
kubectl exec -it -n mysql-operator mysql-operator -- bash
```

MySQL Operator Pod からMySQL Shellを利用して mycluster-0 に接続します。

パスワードが要求されるので、MySQLのSecretに設定したパスワードを入力します。

```
mysqlsh root@mycluster-o.mycluster-instances.default.svc.cluster.local
```

### 2. mycluster-0 に直接接続する場合

```
kubectl exec -it mycluster-0 -- bash
```

mycluster-0 でMySQL Shellを実行

```
mysqlsh --mysql localroot@localhost
```

### 3. MySQL Shellを利用できる専用クライアントPodから接続する場合

```
vim mysqlsh.yaml
```
```
apiVersion: v1
kind: Pod
metadata:
  labels:
  name: mysqlsh
spec:
  containers:
  - name: mysqlsh
    image: cyberblack28/mysqlsh:1.0
    command: ["tail", "-f", "/dev/null"]
```

```
kubectl apply -f mysqlsh.yaml
```

```
kubectl get pods
```
```
NAME                           READY   STATUS    RESTARTS   AGE
mycluster-0                    2/2     Running   0          3h36m
mycluster-1                    2/2     Running   0          3h33m
mycluster-2                    2/2     Running   0          3h31m
mycluster-router-64bqs         1/1     Running   0          3h33m
mysqlsh                        1/1     Running   0          8m23s
nfs-server-788c45b6f5-b2db2    1/1     Running   0          3h33m
wordpress-598746d47b-c8wm5     1/1     Running   0          3h31m
```

```
kubectl exec -it mysqlsh -- bash
```

```
mysqlsh --host=<mycluster Service ClusterIP> --port=6446 --user=root --password=mysqlp@ssword
```

MySQL Shellを終了する場合

```
\quit
```
```
Bye!
```

mysqlshコンテナからexit

```
exit
```

## Sample Application Deploy

```
cd nodetestapp
```

ご自身のイメージリポジトリを指定します。

```
docker image build -t <イメージレポジトリ名>/nodetestapp:1.0
```

```
docker image push <イメージレポジトリ名>/nodetestapp:1.0
```

Pullするご自身のイメージレポジトリに変更します。

```
vim nodetestapp.yaml
```
```
apiVersion: v1
kind: Secret
metadata:
  name: node-auth
type: kubernetes.io/basic-auth
stringData:
  username: node
  password: pass
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nodetestapp
  labels:
    app: nodetestapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nodetestapp-pod
  template:
    metadata:
      labels:
        app: nodetestapp-pod
    spec:
      containers:
      - name: nodetestapp
        image: <イメージレポジトリ名>/nodetestapp:1.0
        ports:
          - containerPort: 8181
        env:
        - name: MYSQL_SERVICE_NAME
          value: "mycluster"
        - name: MYSQL_SERVICE_PORT
          value: "mysqlx"
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: node-auth
              key: username
        - name: MYSQL_PASS
          valueFrom:
            secretKeyRef:
              name: node-auth
              key: password
      restartPolicy: Always 
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nodetestapp
  name: nodetestapp-service
spec:
  ports:
  - port: 8080
    targetPort: 8181
    nodePort: 30007
  selector:
    app: nodetestapp-pod
  type: LoadBalancer
```

サンプルアプリケーションを適用します。

```
kubectl apply -f nodetestapp.yaml
```

nodetestappのPodがRunningになっていることを確認します。

```
kubectl get pods
```
```
NAME                           READY   STATUS    RESTARTS   AGE
mycluster-0                    2/2     Running   0          3h36m
mycluster-1                    2/2     Running   0          3h33m
mycluster-2                    2/2     Running   0          3h31m
mycluster-router-64bqs         1/1     Running   0          3h33m
mysqlsh                        1/1     Running   0          8m23s
nfs-server-788c45b6f5-b2db2    1/1     Running   0          3h33m
nodetestapp-7b8dbd44b6-8xjhq   1/1     Running   0          149m
wordpress-598746d47b-c8wm5     1/1     Running   0          3h31m
```

## WordPress Scale

WordPressのPod数を10に変更してスケールします。

```
kubectl scale deployment wordpress --replicas 10
```

```
kubectl get pods
```
