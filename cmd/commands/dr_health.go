package command

import (
	"github.com/rook/kubectl-rook-ceph/pkg/dr"
	"github.com/spf13/cobra"
)

var DrCmd = &cobra.Command{
	Use:                "dr",
	Short:              "Calls subcommand health",
	DisableFlagParsing: true,
	Args:               cobra.ExactArgs(1),
	PreRun: func(cmd *cobra.Command, args []string) {
		verifyOperatorPodIsRunning(cmd.Context(), clientSets)
	},
}

var healthCmd = &cobra.Command{
	Use:                "health",
	Short:              "Print the ceph status of a peer cluster in a mirroring-enabled cluster.",
	DisableFlagParsing: true,
	Args:               cobra.MaximumNArgs(2),
	Example:            "rook-ceph dr health [Arg]",
	Run: func(cmd *cobra.Command, args []string) {
		dr.Health(cmd.Context(), clientSets, operatorNamespace, cephClusterNamespace, args)
	},
}

func init() {
	DrCmd.AddCommand(healthCmd)
}
