package crossplane

import (
	"context"
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
	xr, err := request.GetObservedCompositeResource(req)
	if err != nil {
		response.Fatal(rsp, errors.Wrapf(err, "cannot get observed composite resource from %T", req))
		return rsp, nil
	}
	repoServer := xr.Resource.Object["spec"].(map[string]interface{})["repoServer"].(string)

	if f.connections == nil {
		f.connections = make(map[string]*grpc.ClientConn)
	}
	conn, exist := f.connections[repoServer]
	if !exist {
		conn, err = grpc.Dial(repoServer, grpc.WithTransportCredentials(insecure.NewCredentials()))
		if err != nil {
			response.Fatal(rsp, errors.Wrapf(err, "unable to  create connection to %s", repoServer))
			return rsp, nil
		}
		f.connections[repoServer] = conn
	}
	state := conn.GetState()
	if state != connectivity.Ready {
		conn.Connect()
	}

	client := fnv1beta1.NewFunctionRunnerServiceClient(conn)
	resp, err := client.RunFunction(ctx, req)

	return resp, err
}
