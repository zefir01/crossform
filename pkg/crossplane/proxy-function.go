package crossplane

import (
	"context"
	"crossform.io/pkg/crossplane/input/v1beta1"
	"github.com/crossplane/crossplane-runtime/pkg/errors"
	"github.com/crossplane/crossplane-runtime/pkg/logging"
	fnv1beta1 "github.com/crossplane/function-sdk-go/proto/v1beta1"
	"github.com/crossplane/function-sdk-go/request"
	"github.com/crossplane/function-sdk-go/response"
	"google.golang.org/grpc"
	"google.golang.org/grpc/connectivity"
	"google.golang.org/grpc/credentials/insecure"
)

// ProxyFunction returns whatever response you ask it to.
type ProxyFunction struct {
	fnv1beta1.UnimplementedFunctionRunnerServiceServer
	Log         logging.Logger
	connections map[string]*grpc.ClientConn
}

// RunFunction runs the ProxyFunction.
func (f *ProxyFunction) RunFunction(ctx context.Context, req *fnv1beta1.RunFunctionRequest) (*fnv1beta1.RunFunctionResponse, error) {
	rsp := response.To(req, response.DefaultTTL)
	var input v1beta1.Input
	err := request.GetInput(req, &input)
	if err != nil {
		response.Fatal(rsp, errors.Wrapf(err, "cannot get input resource in %T", rsp))
		return rsp, nil
	}

	if f.connections == nil {
		f.connections = make(map[string]*grpc.ClientConn)
	}
	conn, exist := f.connections[input.RepoServer]
	if !exist {
		conn, err = grpc.Dial(input.RepoServer, grpc.WithTransportCredentials(insecure.NewCredentials()))
		if err != nil {
			response.Fatal(rsp, errors.Wrapf(err, "unable to  create connection to %s", input.RepoServer))
			return rsp, nil
		}
		f.connections[input.RepoServer] = conn
	}
	state := conn.GetState()
	if state != connectivity.Ready {
		conn.Connect()
	}

	client := fnv1beta1.NewFunctionRunnerServiceClient(conn)
	resp, err := client.RunFunction(ctx, req)

	return resp, err
}
