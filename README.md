Esse repositório contém exemplos de como usar o Gateway API.

Ele foi feito para aqueles que estão iniciando no GatewayAPI, e desejam ter alguns
exemplos prontos de infraestrutura e configurações que podem ser usadas para testar rapidamente
alguma configuração

**Nota** O script de instalação foi testado apenas em ambientes Linux

## Pré requisitos
* Kind (Kubernetes in Docker)
* kubectl
* cURL

Opcional:
* gwctl

## Quickstart

Ao executar `./install.sh` um novo cluster Kind será instalado com MetalLB, kgateway, 
e o deploy da infrastrutura básica (em [infrastructure/]) para os testes

Após isso, os exemplos dentro do diretório [examples] pode ser utilizado para fazer 
o deploy de recursos do Gateway API e testar seu funcionamento

## Testando

O Gateway API faz o deploy de um serviço do tipo LoadBalancer. Esse IP deverá ser utilizado
nas chamadas ao cURL

```
export GATEWAY_IP=$(kubectl get svc -n gateway-ns gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

Assim, as próximas chamadas ao cURL podem ser feitas tal qual:

```
HOST_PORT="user01.example.com:80"
curl --resolve ${HOST_PORT}:${GATEWAY_IP} ${HOST_PORT}/lalala
```

Lembre-se que sempre que você remover e adicionar um Gateway, o IP pode ter sido alterado
e por esse motivo você deve executar o `export GATEWAY_IP....` novamente