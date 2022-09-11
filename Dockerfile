FROM golang:1.11.2 as builder
ENV GOOS=linux GOARCH=amd64 CGO_ENABLED=0
RUN useradd -u 10001 canary

WORKDIR /go/src/github.com/stoehdoi/canary-demo/

COPY . .

RUN make build 


FROM scratch 

WORKDIR /
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /go/src/github.com/stoehdoi/canary-demo/bin/canary-demo /canary-demo
USER canary
EXPOSE 8080
ENTRYPOINT ["/canary-demo"]