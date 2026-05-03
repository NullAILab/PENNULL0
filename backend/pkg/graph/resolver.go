package graph

import (
	"pennull/pkg/config"
	"pennull/pkg/controller"
	"pennull/pkg/database"
	"pennull/pkg/graph/subscriptions"
	"pennull/pkg/providers"
	"pennull/pkg/server/auth"
	"pennull/pkg/templates"

	"github.com/sirupsen/logrus"
)

// This file will not be regenerated automatically.
//
// It serves as dependency injection for your app, add any dependencies you require here.

type Resolver struct {
	DB              database.Querier
	Config          *config.Config
	Logger          *logrus.Entry
	TokenCache      *auth.TokenCache
	DefaultPrompter templates.Prompter
	ProvidersCtrl   providers.ProviderController
	Controller      controller.FlowController
	Subscriptions   subscriptions.SubscriptionsController
}
