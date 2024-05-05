import numpy as np

from .space import Space


class RegularTiling(Space):
    
    def __init__(self, int_dtype, np_random, length, num_agents, num_powers):
        super().__init__(int_dtype, np_random, length, num_agents, num_powers)
        
        self._space = np.zeros((self.length,)*self.NUM_COORDINATES, dtype=self.int_dtype)

        self._agent_points = np.zeros((0, 2), dtype=self.int_dtype)
        for _ in range(self.num_agents):
            point = self.get_unoccupied_point(self.agent_points)
            self._agent_points = np.vstack([self.agent_points, point])

        self._agent_orientations = self.np_random.randint(self.SYMMETRY_ORDER, size=self.num_agents, dtype=self.int_dtype)
    
    @property
    def SYMMETRY_ORDER(self):
        return self._SYMMETRY_ORDER
    
    @property
    def NUM_COORDINATES(self):
        return self._NUM_COORDINATES
    
    @property
    def agent_points(self):
        return self._agent_points

    @property
    def agent_orientations(self):
        return self._agent_orientations

    def random_coordinates(self):
        return np.array([self.np_random.randint(shape, dtype=self.int_dtype) for shape in self._space.shape], dtype=self.int_dtype)
    
    def get_unoccupied_point(self, points):
        while True:
            point = self.random_coordinates()
            if not np.any(np.all(point == points, axis=1)):
                return point
    
    def occupied(self, point):
        return 0 < self._space[tuple(point.T)]
