package repo

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"github.com/pkg/errors"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/selection"
	"k8s.io/client-go/kubernetes"
	ctrl "sigs.k8s.io/controller-runtime"
	"time"
)

type Config struct {
	Url          string
	Revision     string
	UpdatePeriod time.Duration
	Hash         string
	Path         string
}

type AuthData struct {
	PrivateKey string
	Username   string
	Password   string
}

func (c *Config) hash() string {
	hash := md5.Sum([]byte(c.Url + c.Revision))
	return hex.EncodeToString(hash[:])
}

func (c *Config) GetSecretData() (*AuthData, error) {
	clusterClient, _ := kubernetes.NewForConfig(ctrl.GetConfigOrDie())
	l, _ := labels.NewRequirement("crossform.io/secret-type", selection.Equals, []string{"repository"})
	selector := labels.NewSelector()
	selector = selector.Add(*l)
	o := metav1.ListOptions{
		LabelSelector: selector.String(),
	}
	secrets, err := clusterClient.CoreV1().Secrets("default").List(context.TODO(), o)
	if err != nil {
		return nil, errors.Wrap(err, "unable to get secrets")
	}
	var s *corev1.Secret = nil
	for _, v := range secrets.Items {
		if string(v.Data["repository"]) == c.Url {
			s = &v
			break
		}
	}
	if s == nil {
		return nil, errors.Errorf("unable to find secret for repository %s", c.Url)
	}

	tmp, _ := s.Data["sshPrivateKey"]
	key := string(tmp)
	tmp, _ = s.Data["username"]
	username := string(tmp)
	tmp, _ = s.Data["password"]
	pass := string(tmp)

	if key != "" && (username != "" || pass != "") {
		return nil, errors.Errorf("incorrect secret for repository %s, ssh key and username/password specified together", c.Url)
	}
	if key == "" && username == "" {
		return nil, errors.Errorf("incorrect secret for repository %s, username is empty", c.Url)
	}
	if key == "" && username == "" {
		return nil, errors.Errorf("incorrect secret for repository %s, password is empty", c.Url)
	}
	if key == "" && username == "" && pass == "" {
		return nil, errors.Errorf("incorrect secret for repository %s, credentials are empty", c.Url)
	}

	get := func(key string) string {
		v, _ := s.Data[key]
		return string(v)
	}

	data := AuthData{
		PrivateKey: get("sshPrivateKey"),
		Username:   get("username"),
		Password:   get("password"),
	}
	return &data, nil
}

func NewConfig(module *unstructured.Unstructured) (*Config, error) {
	m := module.Object
	spec := m["spec"].(map[string]interface{})

	config := Config{
		Url:          spec["repository"].(string),
		Revision:     spec["revision"].(string),
		UpdatePeriod: time.Second * 30,
	}
	config.Hash = config.hash()
	config.Path = "repos/" + config.Hash
	return &config, nil
}
