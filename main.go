package main

import (
	"crossform.io/pkg/RepoManager"
	"crossform.io/pkg/crossplane"
	"crossform.io/pkg/logger"
	"crossform.io/pkg/repo"
	"fmt"
	"github.com/rs/zerolog"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/dynamic/dynamicinformer"
	"k8s.io/client-go/tools/cache"
	"os"
	ctrl "sigs.k8s.io/controller-runtime"
	"time"
)

func makeModulesInformer(stopper chan struct{}, repoManager *RepoManager.RepoManager, log zerolog.Logger) (cache.SharedIndexInformer, error) {
	clusterClient, _ := dynamic.NewForConfig(ctrl.GetConfigOrDie())
	factory := dynamicinformer.NewFilteredDynamicSharedInformerFactory(clusterClient, time.Hour, corev1.NamespaceAll, nil)

	modulesInformer := factory.ForResource(schema.GroupVersionResource{
		Group:    "crossform.io",
		Version:  "v1alpha1",
		Resource: "xmodules",
	}).Informer()

	_, _ = modulesInformer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj interface{}) {
			u := obj.(*unstructured.Unstructured)
			config, err := repo.NewConfig(u)
			if err != nil {
				log.Error().Err(err).Msg("Unable to unmarshal module")
				return
			}
			repoManager.ConfigUpdates <- config
		},
		UpdateFunc: func(oldObj, newObj interface{}) {
			u := newObj.(*unstructured.Unstructured)
			configNew, err := repo.NewConfig(u)
			if err != nil {
				log.Error().Err(err).Msg("Unable to unmarshal module")
				return
			}
			u = oldObj.(*unstructured.Unstructured)
			configOld, err := repo.NewConfig(u)
			if err != nil {
				log.Error().Err(err).Msg("Unable to unmarshal module")
				return
			}
			if configOld.Hash == configNew.Hash {
				return
			}
			repoManager.ConfigDeletes <- configOld
			repoManager.ConfigUpdates <- configNew
		},
		DeleteFunc: func(obj interface{}) {
			u := obj.(*unstructured.Unstructured)
			config, err := repo.NewConfig(u)
			if err != nil {
				log.Error().Err(err).Msg("Unable to unmarshal module")
				return
			}
			repoManager.ConfigDeletes <- config
		},
	})
	go modulesInformer.Run(stopper)
	if !cache.WaitForCacheSync(stopper, modulesInformer.HasSynced) {
		err := fmt.Errorf("timed out waiting for caches to sync")
		runtime.HandleError(err)
		return nil, err
	}
	return modulesInformer, nil
}

func main() {
	logger.InitLog()
	log := logger.GetLogger("controller")

	repoManager := RepoManager.NewRepoManager()

	stopper := make(chan struct{})
	defer close(stopper)
	defer runtime.HandleCrash()

	_, _ = makeModulesInformer(stopper, repoManager, log)

	functionStart := func() {
		f := crossplane.NewFunction(repoManager)
		err := f.Run()
		if err != nil {
			log.Panic().Err(err).Msg("unable to start crossplane function")
			os.Exit(1)
		}
	}
	go functionStart()

	<-stopper

}
