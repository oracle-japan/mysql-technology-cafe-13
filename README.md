# MySQL Technology Cafe 13

「MySQL Technology Cafe #13」で利用した、デモ環境の構築方法、資材置き場です。

インストール方法は、[MySQL Operator for Kubernetes](https://github.com/mysql/mysql-operator)をベースとしてますが、一部カスタマイズしています。

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

NFSサーバを構築します。最初にPersistentVolumeを作成します。

```
vim nfs-pv.yaml
```

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  storageClassName: nfs
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  #「xxxxxx」を指定する定義
  xxxxxx:
    pdName: xxxxx
    fsType: ext4
```

マニフェストを適用します。

```
kubectl apply -f nfs-pv.yaml
```

次に、PersistentVolumeClaimを作成します。

```
vim nfs-pvc.yaml
```

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc
spec:
  storageClassName: nfs
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
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
NAME                  TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)                               AGE
kubernetes            ClusterIP      10.56.0.1     <none>           443/TCP                               3h14m
mycluster             ClusterIP      10.56.7.48    <none>           6446/TCP,6448/TCP,6447/TCP,6449/TCP   173m
mycluster-instances   ClusterIP      None          <none>           3306/TCP,33060/TCP,33061/TCP          173m
nfs-service           ClusterIP      10.56.9.197   <none>           2049/TCP,20048/TCP,111/TCP            3h5m
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

## WordPress Scale

WordPressのPod数を10に変更してスケールします。

```
kubectl scale deployment wordpress --replicas 10
```

```
kubectl get pods
```
